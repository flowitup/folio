---
phase: 4
title: "API Endpoints"
status: pending
priority: P1
effort: "1.5h"
dependencies: [2, 3]
---

# Phase 4: API Endpoints

## Overview
Expose invoice CRUD as Flask Blueprint routes under `/api/v1/`. Uses exact same pattern as `app/api/v1/labor/worker_routes.py`: `@jwt_required()` + `@require_permission()` decorator stacking, Pydantic request schemas, `get_container()` DI.

## Architecture

```
Endpoints:
  GET    /api/v1/projects/<project_id>/invoices        list (+ ?type= filter)
  POST   /api/v1/projects/<project_id>/invoices        create
  GET    /api/v1/invoices/<invoice_id>                 get detail
  PUT    /api/v1/invoices/<invoice_id>                 update
  DELETE /api/v1/invoices/<invoice_id>                 delete

Permissions:
  read   → project:read          (list, get)
  write  → project:manage_invoices (create, update, delete)
```

## Related Code Files

- **Reference:** `construction-back-end/app/api/v1/labor/worker_routes.py`
- **Reference:** `construction-back-end/app/api/v1/projects/decorators.py` (`require_permission`)
- **Create:** `construction-back-end/app/api/v1/invoices/__init__.py`
- **Create:** `construction-back-end/app/api/v1/invoices/invoice_routes.py`
- **Create:** `construction-back-end/app/api/v1/invoices/schemas.py` (Pydantic request/response schemas)
- **Modify:** `construction-back-end/app/api/v1/__init__.py` — register `invoice_bp` blueprint

## Implementation Steps

1. **Pydantic schemas** in `app/api/v1/invoices/schemas.py`:
   ```python
   class InvoiceItemSchema(BaseModel):
       description: str = Field(..., min_length=1, max_length=500)
       quantity: float = Field(..., gt=0)
       unit_price: float = Field(..., ge=0)

   class CreateInvoiceSchema(BaseModel):
       type: Literal["client", "labor", "supplier"]
       issue_date: str                   # ISO date string, parsed in route
       recipient_name: str = Field(..., min_length=1, max_length=255)
       recipient_address: Optional[str] = None
       notes: Optional[str] = None
       items: list[InvoiceItemSchema] = Field(..., min_length=1)

   class UpdateInvoiceSchema(BaseModel):
       issue_date: Optional[str] = None
       recipient_name: Optional[str] = Field(None, min_length=1, max_length=255)
       recipient_address: Optional[str] = None
       notes: Optional[str] = None
       items: Optional[list[InvoiceItemSchema]] = None
   ```

2. **Blueprint + routes** in `app/api/v1/invoices/invoice_routes.py`:
   ```python
   invoice_bp = Blueprint("invoices", __name__)

   @invoice_bp.route("/projects/<project_id>/invoices", methods=["GET"])
   @jwt_required()
   @require_permission("project:read")
   def list_invoices(project_id: str):
       invoice_type = request.args.get("type")   # optional ?type=client
       try:
           parsed_type = InvoiceType(invoice_type) if invoice_type else None
       except ValueError:
           return _error("ValidationError", f"Invalid type: {invoice_type}", 400)

       results = get_container().list_invoices_usecase.execute(
           ListInvoicesRequest(project_id=UUID(project_id), invoice_type=parsed_type)
       )
       return jsonify({"invoices": [r.__dict__ for r in results], "total": len(results)})


   @invoice_bp.route("/projects/<project_id>/invoices", methods=["POST"])
   @jwt_required()
   @limiter.limit("20 per minute")
   @require_permission("project:manage_invoices")
   def create_invoice(project_id: str):
       try:
           data = CreateInvoiceSchema(**request.get_json())
       except ValidationError as e:
           return _validation_error(e)

       jwt_claims = get_jwt()
       created_by = UUID(jwt_claims["sub"])        # current user ID from JWT

       try:
           result = get_container().create_invoice_usecase.execute(
               CreateInvoiceRequest(
                   project_id=UUID(project_id),
                   created_by=created_by,
                   type=InvoiceType(data.type),
                   issue_date=date.fromisoformat(data.issue_date),
                   recipient_name=data.recipient_name,
                   recipient_address=data.recipient_address,
                   notes=data.notes,
                   items=[i.model_dump() for i in data.items],
               )
           )
       except InvalidInvoiceDataError as e:
           return _error("ValidationError", str(e), 400)
       return jsonify(result.__dict__), 201


   @invoice_bp.route("/invoices/<invoice_id>", methods=["GET"])
   @jwt_required()
   @require_permission("project:read")
   def get_invoice(invoice_id: str):
       try:
           result = get_container().get_invoice_usecase.execute(UUID(invoice_id))
       except InvoiceNotFoundError:
           return _error("NotFound", "Invoice not found", 404)
       return jsonify(result.__dict__)


   @invoice_bp.route("/invoices/<invoice_id>", methods=["PUT"])
   @jwt_required()
   @require_permission("project:manage_invoices")
   def update_invoice(invoice_id: str):
       try:
           data = UpdateInvoiceSchema(**request.get_json())
       except ValidationError as e:
           return _validation_error(e)

       try:
           result = get_container().update_invoice_usecase.execute(
               UpdateInvoiceRequest(invoice_id=UUID(invoice_id), **data.model_dump(exclude_none=True))
           )
       except InvoiceNotFoundError:
           return _error("NotFound", "Invoice not found", 404)
       except InvalidInvoiceDataError as e:
           return _error("ValidationError", str(e), 400)
       return jsonify(result.__dict__)


   @invoice_bp.route("/invoices/<invoice_id>", methods=["DELETE"])
   @jwt_required()
   @require_permission("project:manage_invoices")
   def delete_invoice(invoice_id: str):
       try:
           get_container().delete_invoice_usecase.execute(UUID(invoice_id))
       except InvoiceNotFoundError:
           return _error("NotFound", "Invoice not found", 404)
       return "", 204
   ```

3. **Register blueprint** in `app/api/v1/__init__.py`:
   ```python
   from app.api.v1.invoices.invoice_routes import invoice_bp
   app.register_blueprint(invoice_bp, url_prefix="/api/v1")
   ```

4. **Error helpers** — reuse existing `_error_response` and `_validation_error_response` from labor routes (or extract to shared `app/api/v1/utils.py` if not already there).

## Success Criteria

- [ ] `GET /api/v1/projects/{id}/invoices` returns `{"invoices": [...], "total": N}`
- [ ] `GET /api/v1/projects/{id}/invoices?type=client` returns only client invoices
- [ ] `POST /api/v1/projects/{id}/invoices` returns 201 with created invoice including `invoice_number`
- [ ] `PUT /api/v1/invoices/{id}` returns 200 with updated data; unknown ID returns 404
- [ ] `DELETE /api/v1/invoices/{id}` returns 204; unknown ID returns 404
- [ ] Unauthenticated requests return 401
- [ ] Requests missing `project:manage_invoices` return 403
- [ ] Invalid `?type=` value returns 400

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| `created_by` UUID missing from JWT claims | Check existing JWT structure; add to token claims if absent |
| `dataclass.__dict__` not JSON serializable (UUID, date) | Use `InvoiceResponse.from_entity()` DTO with pre-serialized strings |
