from __future__ import annotations

import io
import os
from typing import Iterable

from django.conf import settings
from django.http import HttpResponse


def _safe_str(v) -> str:
    if v is None:
        return "—"
    if v is True:
        return "نعم"
    if v is False:
        return "لا"
    return str(v)


def xlsx_response(filename: str, sheet_name: str, headers: list[str], rows: Iterable[Iterable]):
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font

    wb = Workbook()
    ws = wb.active
    ws.title = (sheet_name or "Sheet")[:31]
    ws.sheet_view.rightToLeft = True

    ws.append(list(headers))
    for r in rows:
        ws.append(["" if c is None else c for c in r])

    header_font = Font(bold=True)
    for cell in ws[1]:
        cell.font = header_font
        cell.alignment = Alignment(horizontal="right")

    for row in ws.iter_rows(min_row=2):
        for cell in row:
            cell.alignment = Alignment(horizontal="right")

    # Auto width (best-effort)
    for col in ws.columns:
        max_len = 0
        col_letter = col[0].column_letter
        for cell in col:
            try:
                max_len = max(max_len, len(str(cell.value or "")))
            except Exception:
                continue
        ws.column_dimensions[col_letter].width = min(max(10, max_len + 2), 60)

    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)

    resp = HttpResponse(
        buf.getvalue(),
        content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )
    resp["Content-Disposition"] = f'attachment; filename="{filename}"'
    return resp


def _shape_ar(text: str) -> str:
    """Arabic shaping for PDF rendering (ReportLab is not RTL-aware)."""

    try:
        import arabic_reshaper
        from bidi.algorithm import get_display

        reshaped = arabic_reshaper.reshape(text)
        return get_display(reshaped)
    except Exception:
        return text


def _find_pdf_font_path() -> str | None:
    configured = (getattr(settings, "DASHBOARD_PDF_FONT_PATH", "") or "").strip()
    if configured and os.path.exists(configured):
        return configured

    candidates = [
        # Linux (Render)
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf",
        # Windows (dev)
        r"C:\\Windows\\Fonts\\arial.ttf",
        r"C:\\Windows\\Fonts\\tahoma.ttf",
        r"C:\\Windows\\Fonts\\seguiemj.ttf",
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    return None


def pdf_response(
    filename: str,
    title: str,
    headers: list[str],
    rows: Iterable[Iterable],
    landscape: bool = False,
):
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4, landscape as rl_landscape
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

    pagesize = rl_landscape(A4) if landscape else A4

    font_name = "Helvetica"
    font_path = _find_pdf_font_path()
    if font_path:
        try:
            font_name = "DashboardFont"
            pdfmetrics.registerFont(TTFont(font_name, font_path))
        except Exception:
            font_name = "Helvetica"

    style_title = ParagraphStyle(
        name="title",
        fontName=font_name,
        fontSize=14,
        leading=18,
        alignment=2,  # right
    )
    style_cell = ParagraphStyle(
        name="cell",
        fontName=font_name,
        fontSize=9,
        leading=12,
        alignment=2,
    )

    data = []
    data.append([Paragraph(_shape_ar(h), style_cell) for h in headers])
    for r in rows:
        row_cells = []
        for c in r:
            s = _safe_str(c)
            # Shape only if it contains Arabic letters (best-effort)
            if any("\u0600" <= ch <= "\u06FF" for ch in s):
                s = _shape_ar(s)
            row_cells.append(Paragraph(s, style_cell))
        data.append(row_cells)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=pagesize, leftMargin=24, rightMargin=24, topMargin=24, bottomMargin=24)

    table = Table(data, repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#F3F4F6")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#111827")),
                ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#E5E7EB")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("ALIGN", (0, 0), (-1, -1), "RIGHT"),
                ("FONTNAME", (0, 0), (-1, -1), font_name),
                ("FONTSIZE", (0, 0), (-1, -1), 9),
                ("BOTTOMPADDING", (0, 0), (-1, 0), 8),
                ("TOPPADDING", (0, 0), (-1, 0), 8),
            ]
        )
    )

    story = [
        Paragraph(_shape_ar(title), style_title),
        Spacer(1, 12),
        table,
    ]
    doc.build(story)
    buf.seek(0)

    resp = HttpResponse(buf.getvalue(), content_type="application/pdf")
    resp["Content-Disposition"] = f'attachment; filename="{filename}"'
    return resp
