---
phase: 3
title: "Infrastructure Adapters"
status: pending
priority: P1
effort: "1h"
dependencies: [1, 2]
---

# Phase 3: Infrastructure Adapters

## Overview
Implement the SQLAlchemy model and concrete repository that fulfills the `IInvoiceRepository` port. Follows `infrastructure/database/models/worker.py` and `infrastructure/persistence/` patterns exactly.

## Related Code Files

- **Reference:** `construction-back-end/app/infrastructure/database/models/worker.py`
- **Reference:** `construction-back-end/app/infrastructure/persistence/` (labor repo impl)
- **Create:** `construction-back-end/app/infrastructure/database/models/invoice.py`
- **Create:** `construction-back-end/app/infrastructure/persistence/invoice_repository_impl.py`
- **Modify:** `construction-back-end/app/infrastructure/database/models/__init__.py` — export `InvoiceModel`
- **Modify:** `construction-back-end/app/infrastructure/container.py` — wire `InvoiceRepositoryImpl`

## Implementation Steps

1. **SQLAlchemy model** in `app/infrastructure/database/models/invoice.py`:
   ```python
   from sqlalchemy.dialects.postgresql import JSONB

   class InvoiceModel(Base):
       __tablename__ = "invoices"

       id = Column(UUID(as_uuid=True), primary_key=True, default=uuid4)
       project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"),
                           nullable=False, index=True)
       invoice_number = Column(String(20), nullable=False)
       type = Column(
           Enum("client", "labor", "supplier", name="invoicetype"),
           nullable=False, index=True
       )
       issue_date = Column(Date, nullable=False)
       recipient_name = Column(String(255), nullable=False)
       recipient_address = Column(Text, nullable=True)
       notes = Column(Text, nullable=True)
       items = Column(JSONB, nullable=False, default=list)
       created_by = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"),
                           nullable=True)
       created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
       updated_at = Column(
           DateTime,
           default=lambda: datetime.now(timezone.utc),
           onupdate=lambda: datetime.now(timezone.utc),
       )

       project = relationship("ProjectModel")
       creator = relationship("UserModel", foreign_keys=[created_by])

       __table_args__ = (
           UniqueConstraint("project_id", "invoice_number", name="uq_project_invoice_number"),
       )
   ```

2. **Mapper helpers** — two private functions inside the repo impl:
   ```python
   def _model_to_entity(m: InvoiceModel) -> Invoice:
       """Convert ORM model → domain entity. Parses JSONB items back to InvoiceItem list."""
       items = [
           InvoiceItem(
               description=i["description"],
               quantity=Decimal(str(i["quantity"])),
               unit_price=Decimal(str(i["unit_price"])),
           )
           for i in (m.items or [])
       ]
       return Invoice(id=m.id, project_id=m.project_id, ...)

   def _items_to_jsonb(items: list[InvoiceItem]) -> list[dict]:
       """Convert InvoiceItem list → JSONB-serializable dicts. Stores Decimal as float."""
       return [
           {"description": i.description, "quantity": float(i.quantity),
            "unit_price": float(i.unit_price), "total": float(i.total)}
           for i in items
       ]
   ```

3. **Repository implementation** in `app/infrastructure/persistence/invoice_repository_impl.py`:
   ```python
   class InvoiceRepositoryImpl(IInvoiceRepository):
       def __init__(self, session_factory): ...

       def create(self, invoice: Invoice) -> Invoice:
           with self._session() as s:
               model = InvoiceModel(id=invoice.id, ..., items=_items_to_jsonb(invoice.items))
               s.add(model)
               s.commit()
               s.refresh(model)
               return _model_to_entity(model)

       def find_by_id(self, invoice_id: UUID) -> Optional[Invoice]:
           with self._session() as s:
               m = s.get(InvoiceModel, invoice_id)
               return _model_to_entity(m) if m else None

       def list_by_project(self, project_id: UUID,
                           invoice_type: Optional[InvoiceType] = None) -> list[Invoice]:
           with self._session() as s:
               q = s.query(InvoiceModel).filter_by(project_id=project_id)
               if invoice_type:
                   q = q.filter(InvoiceModel.type == invoice_type.value)
               return [_model_to_entity(m) for m in q.order_by(InvoiceModel.created_at.desc())]

       def update(self, invoice: Invoice) -> Invoice:
           with self._session() as s:
               m = s.get(InvoiceModel, invoice.id)
               # apply field updates + items JSONB
               s.commit(); s.refresh(m)
               return _model_to_entity(m)

       def delete(self, invoice_id: UUID) -> bool:
           with self._session() as s:
               m = s.get(InvoiceModel, invoice_id)
               if not m: return False
               s.delete(m); s.commit()
               return True

       def next_invoice_number(self, project_id: UUID) -> str:
           """Generate next INV-YYYY-NNNN. Uses MAX query + 1, safe for low concurrency."""
           with self._session() as s:
               year = datetime.now().year
               prefix = f"INV-{year}-"
               last = (s.query(InvoiceModel)
                         .filter(InvoiceModel.project_id == project_id,
                                 InvoiceModel.invoice_number.like(f"{prefix}%"))
                         .order_by(InvoiceModel.invoice_number.desc())
                         .first())
               n = 1
               if last:
                   try: n = int(last.invoice_number.split("-")[-1]) + 1
                   except ValueError: pass
               return f"{prefix}{n:04d}"
   ```

4. **Register in container** — in `app/infrastructure/container.py`:
   ```python
   from app.infrastructure.persistence.invoice_repository_impl import InvoiceRepositoryImpl
   invoice_repo = InvoiceRepositoryImpl(session_factory)
   self.create_invoice_usecase = CreateInvoiceUseCase(invoice_repo)
   # ... rest of use cases
   ```

5. **Export model** — add `InvoiceModel` to `app/infrastructure/database/models/__init__.py` so Alembic autogenerates correctly.

## Success Criteria

- [ ] `InvoiceModel` registered in SQLAlchemy metadata (Alembic can see it)
- [ ] `_model_to_entity` correctly parses JSONB items back to `InvoiceItem` with `Decimal` types
- [ ] `next_invoice_number` returns `INV-2026-0001` for first invoice, `INV-2026-0002` for second
- [ ] `list_by_project` returns results ordered newest-first
- [ ] `list_by_project` with `invoice_type` filter returns only matching type
- [ ] All 6 repo methods implemented and wired into container
