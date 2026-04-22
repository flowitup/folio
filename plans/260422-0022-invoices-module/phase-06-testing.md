---
phase: 6
title: "Testing"
status: pending
priority: P2
effort: "0.5h"
dependencies: [4, 5]
---

# Phase 6: Testing

## Overview
Write unit tests for use cases (backend) and component tests for the invoice form (frontend). Follows existing test patterns in `tests/` (pytest) and `src/__tests__/` (vitest + RTL).

## Related Code Files

- **Reference:** `construction-back-end/tests/` (existing pytest test structure)
- **Reference:** `construction-front-end/src/__tests__/` (existing vitest tests)
- **Create:** `construction-back-end/tests/unit/application/test_create_invoice_use_case.py`
- **Create:** `construction-back-end/tests/unit/application/test_list_invoices_use_case.py`
- **Create:** `construction-back-end/tests/unit/domain/test_invoice_entity.py`
- **Create:** `construction-front-end/src/__tests__/invoice-form.test.tsx`

## Implementation Steps

1. **Domain entity tests** (`test_invoice_entity.py`):
   ```python
   def test_invoice_total_amount_sums_items():
       item1 = InvoiceItem(description="A", quantity=Decimal("2"), unit_price=Decimal("100"))
       item2 = InvoiceItem(description="B", quantity=Decimal("1"), unit_price=Decimal("50"))
       invoice = Invoice(id=uuid4(), ..., items=[item1, item2])
       assert invoice.total_amount == Decimal("250")

   def test_invoice_item_total_is_computed():
       item = InvoiceItem(description="X", quantity=Decimal("3"), unit_price=Decimal("10"))
       assert item.total == Decimal("30")

   def test_invoice_equality_by_id():
       id_ = uuid4()
       inv1 = Invoice(id=id_, ...)
       inv2 = Invoice(id=id_, ...)
       assert inv1 == inv2
   ```

2. **Use case tests** (`test_create_invoice_use_case.py`) — mock repository:
   ```python
   @pytest.fixture
   def mock_repo():
       repo = MagicMock(spec=IInvoiceRepository)
       repo.next_invoice_number.return_value = "INV-2026-0001"
       repo.create.side_effect = lambda inv: inv
       return repo

   def test_create_invoice_success(mock_repo):
       uc = CreateInvoiceUseCase(mock_repo)
       req = CreateInvoiceRequest(
           project_id=uuid4(), created_by=uuid4(),
           type=InvoiceType.CLIENT, issue_date=date.today(),
           recipient_name="ACME Corp",
           items=[{"description": "Work", "quantity": 10, "unit_price": 50}]
       )
       result = uc.execute(req)
       assert result.invoice_number == "INV-2026-0001"
       assert result.total_amount == 500.0
       mock_repo.create.assert_called_once()

   def test_create_invoice_empty_recipient_raises():
       uc = CreateInvoiceUseCase(MagicMock())
       with pytest.raises(InvalidInvoiceDataError, match="recipient"):
           uc.execute(CreateInvoiceRequest(..., recipient_name="", items=[...]))

   def test_create_invoice_zero_quantity_raises():
       uc = CreateInvoiceUseCase(MagicMock())
       with pytest.raises(InvalidInvoiceDataError, match="quantity"):
           uc.execute(CreateInvoiceRequest(..., items=[{"quantity": 0, ...}]))
   ```

3. **List use case tests** (`test_list_invoices_use_case.py`):
   ```python
   def test_list_invoices_filters_by_type(mock_repo):
       mock_repo.list_by_project.return_value = [make_invoice(type=InvoiceType.CLIENT)]
       uc = ListInvoicesUseCase(mock_repo)
       result = uc.execute(ListInvoicesRequest(project_id=uuid4(), invoice_type=InvoiceType.CLIENT))
       mock_repo.list_by_project.assert_called_with(ANY, InvoiceType.CLIENT)
       assert len(result) == 1

   def test_list_invoices_no_filter_returns_all(mock_repo):
       mock_repo.list_by_project.return_value = [make_invoice(), make_invoice()]
       result = ListInvoicesUseCase(mock_repo).execute(ListInvoicesRequest(project_id=uuid4()))
       assert len(result) == 2
   ```

4. **Frontend form test** (`invoice-form.test.tsx`):
   ```typescript
   describe("InvoiceForm", () => {
     it("shows validation error when recipient is empty", async () => {
       render(<InvoiceForm onSubmit={vi.fn()} />);
       await userEvent.click(screen.getByRole("button", { name: /save/i }));
       expect(screen.getByText(/recipient.*required/i)).toBeInTheDocument();
     });

     it("computes line item total on quantity change", async () => {
       render(<InvoiceForm onSubmit={vi.fn()} />);
       await userEvent.type(screen.getByLabelText(/unit price/i), "50");
       await userEvent.type(screen.getByLabelText(/quantity/i), "3");
       expect(screen.getByText("150.00")).toBeInTheDocument();
     });

     it("adds and removes line items", async () => {
       render(<InvoiceForm onSubmit={vi.fn()} />);
       await userEvent.click(screen.getByRole("button", { name: /add item/i }));
       expect(screen.getAllByLabelText(/description/i)).toHaveLength(2);
       await userEvent.click(screen.getAllByRole("button", { name: /remove/i })[0]);
       expect(screen.getAllByLabelText(/description/i)).toHaveLength(1);
     });
   });
   ```

5. **Run backend tests**: `cd construction-back-end && uv run pytest tests/unit/application/test_create_invoice_use_case.py tests/unit/application/test_list_invoices_use_case.py tests/unit/domain/test_invoice_entity.py -v`

6. **Run frontend tests**: `cd construction-front-end && npm test -- src/__tests__/invoice-form.test.tsx`

## Success Criteria

- [ ] `test_invoice_total_amount_sums_items` passes
- [ ] `test_create_invoice_success` passes with correct `invoice_number` and `total_amount`
- [ ] `test_create_invoice_empty_recipient_raises` passes
- [ ] `test_create_invoice_zero_quantity_raises` passes
- [ ] `test_list_invoices_filters_by_type` passes
- [ ] Frontend: recipient validation test passes
- [ ] Frontend: line item total computation test passes
- [ ] All existing tests still pass (`uv run pytest` + `npm test`)
