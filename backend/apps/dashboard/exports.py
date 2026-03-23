from __future__ import annotations

from io import BytesIO

from django.http import HttpResponse


def _as_text(value) -> str:
    if value is None:
        return ""
    return str(value)


def xlsx_response(filename: str, sheet_name: str, headers: list[str], rows: list[list]) -> HttpResponse:
    from openpyxl import Workbook

    wb = Workbook()
    ws = wb.active
    ws.title = (sheet_name or "sheet")[:31]
    ws.sheet_view.rightToLeft = True

    ws.append([_as_text(h) for h in headers])
    for row in rows:
        ws.append([_as_text(v) for v in row])

    buffer = BytesIO()
    wb.save(buffer)
    buffer.seek(0)

    response = HttpResponse(
        buffer.getvalue(),
        content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )
    response["Content-Disposition"] = f'attachment; filename="{filename}"'
    return response


def _shape_ar(text: str) -> str:
    value = _as_text(text)
    try:
        import arabic_reshaper
        from bidi.algorithm import get_display

        return get_display(arabic_reshaper.reshape(value))
    except Exception:
        return value


def pdf_response(
    filename: str,
    title: str,
    headers: list[str],
    rows: list[list],
    *,
    landscape: bool = False,
) -> HttpResponse:
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.lib.units import mm
    from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

    try:
        from reportlab.lib.pagesizes import landscape as rl_landscape

        page_size = rl_landscape(A4) if landscape else A4
    except Exception:
        page_size = A4

    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=page_size,
        rightMargin=10 * mm,
        leftMargin=10 * mm,
        topMargin=12 * mm,
        bottomMargin=12 * mm,
    )

    styles = getSampleStyleSheet()
    content = [Paragraph(_shape_ar(title), styles["Title"]), Spacer(1, 8)]

    table_data = [[_shape_ar(h) for h in headers]]
    for row in rows:
        table_data.append([_shape_ar(_as_text(v)) for v in row])

    table = Table(table_data, repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#6f1d78")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#d182d1")),
                ("FONTNAME", (0, 0), (-1, -1), "Helvetica"),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f7f0f8")]),
            ]
        )
    )
    content.append(table)
    doc.build(content)
    buffer.seek(0)

    response = HttpResponse(buffer.getvalue(), content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="{filename}"'
    return response

