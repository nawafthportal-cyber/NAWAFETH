from django.urls import path

from .views import (
    InvoiceCreateView,
    MyInvoicesListView,
    InvoiceDetailView,
    CompleteMockPaymentView,
    InitPaymentView,
    WebhookReceiverView,
)

urlpatterns = [
    path("invoices/", InvoiceCreateView.as_view(), name="invoice_create"),
    path("invoices/my/", MyInvoicesListView.as_view(), name="my_invoices"),
    path("invoices/<int:pk>/", InvoiceDetailView.as_view(), name="invoice_detail"),
    path("invoices/<int:pk>/init-payment/", InitPaymentView.as_view(), name="invoice_init_payment"),
    path("invoices/<int:pk>/complete-mock-payment/", CompleteMockPaymentView.as_view(), name="invoice_complete_mock_payment"),
    path("webhooks/<str:provider>/", WebhookReceiverView.as_view(), name="webhook_receiver"),
]
