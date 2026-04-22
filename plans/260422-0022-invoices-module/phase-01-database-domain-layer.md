---
phase: 1
title: "Database & Domain Layer"
status: pending
priority: P1
effort: "1h"
dependencies: []
---

# Phase 1: Database & Domain Layer

## Overview
Create the `Invoice` domain entity, value objects, repository interface (port), domain exceptions, and Alembic migration for the `invoices` table. Follows exact patterns from `domain/labor/`.

## Requirements
- Functional: Invoice entity with UUID PK, project FK, type enum, JSONB items, auto invoice number
- Non-functional: Immutable dataclass, UTC timestamps, Decimal for money

## Architecture

```
Invoice (domain entity)
├── id: UUID
├── project_id: UUID
├── invoice_number: str          # INV-YYYY-NNNN (generated at creation)
├── type: InvoiceType            # Enum: client | labor | supplier
├── issue_date: date
├── recipient_name: str
├── recipient_address: str | None
├── notes: str | None
├── items: list[InvoiceItem]     # JSONB — embedded value object
├── created_by: UUID
├── created_at: datetime
└── updated_at: datetime

InvoiceItem (value object — no identity)
├── description: str
├── quantity: Decimal
├── unit_price: Decimal
└── total: Decimal               # computed: quantity * unit_price
```

## Related Code Files

- **Create:** `construction-back-end/app/domain/entities/invoice.py`
- **Create:** `construction-back-end/app/domain/value_objects/invoice_item.py`
- **Create:** `construction-back-end/app/domain/exceptions/invoice_exceptions.py`
- **Create:** `construction-back-end/app/application/invoice/ports.py`
- **Create:** `construction-back-end/migrations/versions/xxxx_add_invoices_table.py`
- **Modify:** `construction-back-end/scripts/seed_auth.py` — add `project:manage_invoices` permission + assign to admin/manager roles

## Implementation Steps

1. **Create `InvoiceType` enum** in `app/domain/entities/invoice.py`:
   ```python
   from enum import Enum
   class InvoiceType(str, Enum):
       CLIENT = "client"
       LABOR = "labor"
       SUPPLIER = "supplier"
   ```

2. **Create `InvoiceItem` value object** in `app/domain/value_objects/invoice_item.py`:
   ```python
   @dataclass(frozen=True)
   class InvoiceItem:
       description: str
       quantity: Decimal
       unit_price: Decimal

       @property
       def total(self) -> Decimal:
           return self.quantity * self.unit_price
   ```

3. **Create `Invoice` domain entity** in `app/domain/entities/invoice.py`:
   ```python
   @dataclass(slots=True)
   class Invoice:
       id: UUID
       project_id: UUID
       invoice_number: str
       type: InvoiceType
       issue_date: date
       recipient_name: str
       created_by: UUID
       created_at: datetime
       updated_at: datetime
       items: list[InvoiceItem] = field(default_factory=list)
       recipient_address: Optional[str] = None
       notes: Optional[str] = None

       @property
       def total_amount(self) -> Decimal:
           return sum(item.total for item in self.items)

       def __eq__(self, other: object) -> bool:
           if not isinstance(other, Invoice): return NotImplemented
           return self.id == other.id

       def __hash__(self) -> int:
           return hash(self.id)
   ```

4. **Create domain exceptions** in `app/domain/exceptions/invoice_exceptions.py`:
   ```python
   class InvoiceNotFoundError(Exception): pass
   class InvalidInvoiceDataError(ValueError): pass
   class InvoiceNumberConflictError(Exception): pass
   ```

5. **Create repository port** in `app/application/invoice/ports.py`:
   ```python
   class IInvoiceRepository(ABC):
       @abstractmethod
       def create(self, invoice: Invoice) -> Invoice: ...
       @abstractmethod
       def find_by_id(self, invoice_id: UUID) -> Optional[Invoice]: ...
       @abstractmethod
       def list_by_project(self, project_id: UUID, invoice_type: Optional[InvoiceType] = None) -> list[Invoice]: ...
       @abstractmethod
       def update(self, invoice: Invoice) -> Invoice: ...
       @abstractmethod
       def delete(self, invoice_id: UUID) -> bool: ...
       @abstractmethod
       def next_invoice_number(self, project_id: UUID) -> str: ...
   ```

6. **Alembic migration** — generate with `flask db migrate -m "add_invoices_table"` then verify/edit:
   ```python
   op.create_table('invoices',
       sa.Column('id', sa.UUID(), nullable=False),
       sa.Column('project_id', sa.UUID(), nullable=False),
       sa.Column('invoice_number', sa.String(20), nullable=False),
       sa.Column('type', sa.Enum('client','labor','supplier', name='invoicetype'), nullable=False),
       sa.Column('issue_date', sa.Date(), nullable=False),
       sa.Column('recipient_name', sa.String(255), nullable=False),
       sa.Column('recipient_address', sa.Text(), nullable=True),
       sa.Column('notes', sa.Text(), nullable=True),
       sa.Column('items', postgresql.JSONB(), nullable=False, server_default='[]'),
       sa.Column('created_by', sa.UUID(), nullable=False),
       sa.Column('created_at', sa.DateTime(), nullable=True),
       sa.Column('updated_at', sa.DateTime(), nullable=True),
       sa.ForeignKeyConstraint(['project_id'], ['projects.id'], ondelete='CASCADE'),
       sa.ForeignKeyConstraint(['created_by'], ['users.id'], ondelete='SET NULL'),
       sa.PrimaryKeyConstraint('id'),
       sa.UniqueConstraint('project_id', 'invoice_number', name='uq_project_invoice_number')
   )
   op.create_index('ix_invoices_project_id', 'invoices', ['project_id'])
   op.create_index('ix_invoices_type', 'invoices', ['type'])
   ```

7. **Update seed** in `scripts/seed_auth.py`:
   - Add `{"name": "project:manage_invoices", "resource": "project", "action": "manage_invoices"}` to `DEFAULT_PERMISSIONS`
   - Add `"project:manage_invoices"` to manager role's permissions list

## Success Criteria

- [ ] `Invoice` entity + `InvoiceItem` value object created with correct types
- [ ] `InvoiceType` enum has client/labor/supplier values
- [ ] `IInvoiceRepository` port has all 6 methods including `next_invoice_number`
- [ ] Domain exceptions created
- [ ] Migration runs cleanly: `flask db upgrade` — no errors
- [ ] `invoices` table exists with JSONB items column and unique constraint on `(project_id, invoice_number)`
- [ ] `project:manage_invoices` permission exists in seed data

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| JSONB not available on SQLite (test DB) | Use `sa.JSON()` fallback or set tests to use PostgreSQL |
| Invoice number collision on concurrent creates | `next_invoice_number` uses DB sequence or `SELECT MAX(...) + 1` with row lock |
| `InvoiceType` enum already registered in PG | Use `checkfirst=True` in enum creation |
