"""
بوابة العميل للخدمات الإضافية — Phase 6.

جميع الـ views تستخدم @dashboard_access_required("client_extras")
وتُعرض ضمن /dashboard/client/extras/.
"""
from __future__ import annotations

from django.contrib import messages
from django.http import HttpRequest
from django.shortcuts import get_object_or_404, redirect, render

from apps.billing.pricing import calculate_extras_price, get_extras_catalog
from apps.extras.models import ExtraPurchase
from apps.extras.services import create_extra_purchase_checkout

from .access import dashboard_access_required


@dashboard_access_required("client_extras")
def client_extras_catalog(request: HttpRequest):
    """عرض كتالوج الخدمات الإضافية المتاحة."""
    catalog = get_extras_catalog()
    items = []
    for sku, info in catalog.items():
        try:
            pricing = calculate_extras_price(sku)
        except (ValueError, Exception):
            continue
        items.append({
            "sku": sku,
            "title": info.get("title", sku),
            "subtotal": pricing["subtotal"],
            "vat_percent": pricing["vat_percent"],
            "vat_amount": pricing["vat_amount"],
            "total": pricing["total"],
            "currency": pricing["currency"],
        })
    return render(request, "dashboard/client_extras/catalog.html", {"items": items})


@dashboard_access_required("client_extras")
def client_extras_purchases(request: HttpRequest):
    """مشتريات العميل الإضافية."""
    purchases = (
        ExtraPurchase.objects
        .filter(user=request.user)
        .select_related("invoice")
        .order_by("-created_at")
    )
    return render(request, "dashboard/client_extras/purchases.html", {"purchases": purchases})


@dashboard_access_required("client_extras", write=True)
def client_extras_buy(request: HttpRequest, sku: str):
    """شراء خدمة إضافية."""
    if request.method != "POST":
        return redirect("dashboard:client_extras_catalog")

    try:
        purchase = create_extra_purchase_checkout(user=request.user, sku=sku)
        messages.success(request, f"تم إنشاء طلب الشراء — الفاتورة #{purchase.invoice.code}")
    except ValueError as e:
        messages.error(request, str(e))
        return redirect("dashboard:client_extras_catalog")

    return redirect("dashboard:client_extras_purchases")


@dashboard_access_required("client_extras")
def client_extras_invoice(request: HttpRequest, invoice_id: int):
    """عرض تفاصيل فاتورة خدمة إضافية."""
    purchase = get_object_or_404(
        ExtraPurchase.objects.select_related("invoice"),
        invoice_id=invoice_id,
        user=request.user,
    )
    return render(request, "dashboard/client_extras/invoice.html", {
        "purchase": purchase,
        "invoice": purchase.invoice,
    })
