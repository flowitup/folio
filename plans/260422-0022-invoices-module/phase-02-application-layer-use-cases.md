---
phase: 2
title: "Application Layer (Use Cases)"
status: pending
priority: P1
effort: "1.5h"
dependencies: [1]
---

# Phase 2: Application Layer (Use Cases)

## Overview
Implement 5 use cases (create, list, get, update, delete) following the Request/Response DTO pattern from `app/application/labor/`. Each use case validates inputs, delegates to the repository port, and returns serializable response objects.

## Requirements
- Functional: CRUD for invoices + auto invoice number generation
- Non-functional: Validation before persistence, UTC timestamps, no business logic in API layer

## Architecture

```
application/invoice/
├── ports.py               # IInvoiceRepository (from Phase 1)
├── create_invoice.py      # CreateInvoiceUseCase
├── list_invoices.py       # ListInvoicesUseCase
├── get_invoice.py         # GetInvoiceUseCase
├── update_invoice.py      # UpdateInvoiceUseCase
└── delete_invoice.py      # DeleteInvoiceUseCase
```

Each use case:
- `__init__(self, invoice_repo: IInvoiceRepository)`
- `execute(self, request: XxxRequest) -> XxxResponse`

## Related Code Files

- **Reference:** `construction-back-end/app/application/labor/create_worker.py` (pattern to follow)
- **Create:** `construction-back-end/app/application/invoice/create_invoice.py`
- **Create:** `construction-back-end/app/application/invoice/list_invoices.py`
- **Create:** `construction-back-end/app/application/invoice/get_invoice.py`
- **Create:** `construction-back-end/app/application/invoice/update_invoice.py`
- **Create:** `construction-back-end/app/application/invoice/delete_invoice.py`

## Implementation Steps

1. **`create_invoice.py`**:
   ```python
   @dataclass
   class CreateInvoiceRequest:
       project_id: UUID
       created_by: UUID
       type: InvoiceType
       issue_date: date
       recipient_name: str
       items: list[dict]            # raw dicts, validated inside use case
       recipient_address: Optional[str] = None
       notes: Optional[str] = None

   class CreateInvoiceUseCase:
       def __init__(self, invoice_repo: IInvoiceRepository): ...

       def execute(self, request: CreateInvoiceRequest) -> InvoiceResponse:
           # 1. Validate recipient_name not empty
           # 2. Validate items: each must have description, quantity > 0, unit_price >= 0
           # 3. Build InvoiceItem list from raw dicts
           # 4. Generate invoice_number via repo.next_invoice_number(project_id)
           # 5. Create Invoice entity with uuid4(), utcnow()
           # 6. repo.create(invoice) → saved
           # 7. Return InvoiceResponse.from_entity(saved)
   ```

2. **`list_invoices.py`**:
   ```python
   @dataclass
   class ListInvoicesRequest:
       project_id: UUID
       invoice_type: Optional[InvoiceType] = None   # filter by type

   class ListInvoicesUseCase:
       def execute(self, request: ListInvoicesRequest) -> list[InvoiceResponse]:
           invoices = self._repo.list_by_project(request.project_id, request.invoice_type)
           return [InvoiceResponse.from_entity(inv) for inv in invoices]
   ```

3. **`get_invoice.py`**:
   ```python
   class GetInvoiceUseCase:
       def execute(self, invoice_id: UUID) -> InvoiceResponse:
           invoice = self._repo.find_by_id(invoice_id)
           if not invoice:
               raise InvoiceNotFoundError(f"Invoice {invoice_id} not found")
           return InvoiceResponse.from_entity(invoice)
   ```

4. **`update_invoice.py`**:
   ```python
   @dataclass
   class UpdateInvoiceRequest:
       invoice_id: UUID
       recipient_name: Optional[str] = None
       issue_date: Optional[date] = None
       items: Optional[list[dict]] = None
       recipient_address: Optional[str] = None
       notes: Optional[str] = None
       # type is immutable after creation

   class UpdateInvoiceUseCase:
       def execute(self, request: UpdateInvoiceRequest) -> InvoiceResponse:
           # 1. find_by_id or raise InvoiceNotFoundError
           # 2. Apply only non-None fields (partial update)
           # 3. Re-validate items if provided
           # 4. Set updated_at = utcnow()
           # 5. repo.update(invoice) → saved
           # 6. Return InvoiceResponse.from_entity(saved)
   ```

5. **`delete_invoice.py`**:
   ```python
   class DeleteInvoiceUseCase:
       def execute(self, invoice_id: UUID) -> None:
           found = self._repo.find_by_id(invoice_id)
           if not found:
               raise InvoiceNotFoundError(...)
           self._repo.delete(invoice_id)
   ```

6. **Shared `InvoiceResponse` DTO** (put in `application/invoice/dtos.py`):
   ```python
   @dataclass
   class InvoiceItemResponse:
       description: str
       quantity: float
       unit_price: float
       total: float

   @dataclass
   class InvoiceResponse:
       id: str
       project_id: str
       invoice_number: str
       type: str
       issue_date: str          # ISO format
       recipient_name: str
       recipient_address: Optional[str]
       notes: Optional[str]
       items: list[InvoiceItemResponse]
       total_amount: float
       created_by: str
       created_at: str
       updated_at: str

       @classmethod
       def from_entity(cls, inv: Invoice) -> "InvoiceResponse": ...
   ```

7. **Wire use cases into DI container** — add to `app/infrastructure/container.py` (or wherever `get_container()` is defined):
   ```python
   self.create_invoice_usecase = CreateInvoiceUseCase(invoice_repo)
   self.list_invoices_usecase = ListInvoicesUseCase(invoice_repo)
   self.get_invoice_usecase = GetInvoiceUseCase(invoice_repo)
   self.update_invoice_usecase = UpdateInvoiceUseCase(invoice_repo)
   self.delete_invoice_usecase = DeleteInvoiceUseCase(invoice_repo)
   ```

## Success Criteria

- [ ] All 5 use cases created with Request/Response dataclasses
- [ ] `InvoiceResponse.from_entity()` correctly serializes all fields including `total_amount`
- [ ] Validation raises `InvalidInvoiceDataError` for: empty recipient_name, items with quantity ≤ 0, items with unit_price < 0
- [ ] `GetInvoiceUseCase` raises `InvoiceNotFoundError` for missing ID
- [ ] `DeleteInvoiceUseCase` raises `InvoiceNotFoundError` before attempting delete
- [ ] All use cases registered in DI container

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Partial update mutating immutable dataclass | Use `dataclasses.replace()` for Invoice entity updates |
| JSONB items round-trip loses Decimal precision | Store as strings in JSONB, parse back with `Decimal(str(...))` |
