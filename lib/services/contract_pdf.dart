import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/questionnaire.dart';
import '../providers/contract_state.dart';
import '../widgets/common_widgets.dart';

/// توليد ملف العقد النهائي أو التقرير المرحلي بصيغة PDF
class ContractPdf {
  ContractPdf._();

  static const _navy = PdfColor.fromInt(0xFF0F1B2E);
  static const _gold = PdfColor.fromInt(0xFFA3811C);
  static const _muted = PdfColor.fromInt(0xFF5B6B82);
  static const _line = PdfColor.fromInt(0xFFD9D2BE);

  static final _dt = DateFormat('yyyy/MM/dd HH:mm');

  static Future<void> share(ContractState state, ContractSession s, {required bool interim}) async {
    final name = interim
        ? 'تقرير_مرحلي_${s.companyName}.pdf'
        : 'عقد_تأسيس_${s.companyName}.pdf';
    await Printing.layoutPdf(
      name: name,
      onLayout: (format) => build(state, s, interim: interim, format: format),
    );
  }

  static Future<Uint8List> buildBytes(ContractState state, ContractSession s, {required bool interim}) =>
      build(state, s, interim: interim, format: PdfPageFormat.a4);

  static Future<Uint8List> build(
    ContractState state,
    ContractSession s, {
    required bool interim,
    required PdfPageFormat format,
  }) async {
    // خط نسخ عربي رسمي للعقد، مع خط لاتيني احتياطي للأرقام والرموز الإنجليزية
    final regular = await PdfGoogleFonts.notoNaskhArabicRegular();
    final bold = await PdfGoogleFonts.notoNaskhArabicBold();
    final latin = await PdfGoogleFonts.notoSansRegular();
    final doc = pw.Document(
      title: interim ? 'تقرير مرحلي - ${s.companyName}' : 'عقد تأسيس - ${s.companyName}',
      author: 'ميثاق',
      theme: pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [latin]),
    );

    final agreed = s.records.where((r) => r.status == ClauseStatus.agreed).toList();
    final neutralized = s.records.where((r) => r.status == ClauseStatus.neutralized).toList();
    final open = s.records
        .where((r) => r.status != ClauseStatus.agreed && r.status != ClauseStatus.neutralized)
        .toList();
    final now = DateTime.now();

    String titleOf(ClauseRecord r) {
      final q = state.question(r.questionId);
      final p = s.partners.where((x) => x.id == r.concernedPartnerId).firstOrNull;
      return p == null ? q.title : '${q.title} – ${p.name}';
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 50),
        header: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          margin: const pw.EdgeInsets.only(bottom: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _gold, width: 1.2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('ميثاق · نظام العقود والحوكمة الذكي',
                  style: pw.TextStyle(color: _gold, fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.Text(interim ? 'تقرير مرحلي – غير نهائي' : 'عقد تأسيس نهائي',
                  style: const pw.TextStyle(color: _muted, fontSize: 9)),
            ],
          ),
        ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('رقم المستند ${s.id} · صدر ${_dt.format(now)}',
                style: const pw.TextStyle(color: _muted, fontSize: 8)),
            pw.Text('صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
                style: const pw.TextStyle(color: _muted, fontSize: 8)),
          ],
        ),
        build: (ctx) => [
          pw.Center(
            child: pw.Text(
              interim ? 'تقرير مرحلي بالبنود المتراضى عليها' : 'عقد تأسيس ${s.companyType}',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _navy),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(s.companyName,
                style: pw.TextStyle(fontSize: 16, color: _gold, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 16),
          _kv([
            ('الشكل القانوني', s.companyType),
            ('رأس المال', formatCurrency(s.capital, s.currency)),
            ('عملة العقد', '${s.currency.label} (${s.currency.code})'),
            ('بدء الجلسات', _dt.format(s.createdAt)),
            ('عدد الجلسات', '${s.sittings}'),
            if (!interim && s.completedAt != null) ('تاريخ الاعتماد', _dt.format(s.completedAt!)),
          ]),
          pw.SizedBox(height: 14),
          _heading('جدول الشركاء'),
          pw.TableHelper.fromTextArray(
            headers: ['الاسم', 'رقم الهوية', 'الجوال', 'الحصة'],
            data: s.partners
                // رقم الجوال يُكتب من اليسار لليمين حتى لا ينقلب ترتيب أرقامه
                .map((p) => [
                      p.name,
                      p.nationalId.isEmpty ? '—' : p.nationalId,
                      pw.Text(p.phone,
                          textDirection: pw.TextDirection.ltr,
                          style: const pw.TextStyle(fontSize: 10)),
                      '${p.equity.toStringAsFixed(p.equity % 1 == 0 ? 0 : 1)}%',
                    ])
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: _navy),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignment: pw.Alignment.centerRight,
            border: pw.TableBorder.all(color: _line, width: 0.6),
          ),
          pw.SizedBox(height: 16),
          _heading(interim ? 'البنود المتراضى عليها حتى الآن (${agreed.length})' : 'بنود العقد'),
          ...agreed.asMap().entries.map((e) {
            final r = e.value;
            final res = state.quorum(s, r);
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('البند ${e.key + 1}: ${titleOf(r)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11.5, color: _navy)),
                  pw.SizedBox(height: 3),
                  pw.Text(state.renderClause(s, r),
                      style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 4)),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'اعتُمد ${r.resolvedAt == null ? '' : _dt.format(r.resolvedAt!)} · موافقة ${res.agreeShare.toStringAsFixed(1)}% من الحصص · الجولة ${r.round} · '
                    '${r.votes.values.map((v) => '${s.partners.where((p) => p.id == v.partnerId).firstOrNull?.name ?? ''}: ${v.ballot.label} (${_dt.format(v.at)})').join('، ')}',
                    style: const pw.TextStyle(fontSize: 7.5, color: _muted),
                  ),
                ],
              ),
            );
          }),
          if (neutralized.isNotEmpty) ...[
            _heading('بنود محيّدة باتفاق الشركاء'),
            pw.Text(neutralized.map(titleOf).join('، '),
                style: const pw.TextStyle(fontSize: 10, color: _muted)),
            pw.SizedBox(height: 10),
          ],
          if (interim && open.isNotEmpty) ...[
            _heading('بنود لم تُحسم بعد (${open.length})'),
            ...open.map((r) => _bullet('${titleOf(r)} – ${r.status.label}', 10)),
            pw.SizedBox(height: 10),
          ],
          if (state.generatedRules(s).isNotEmpty) ...[
            _heading('ملحق: القواعد الرقابية المولدة من العقد'),
            ...state.generatedRules(s).map((t) => _bullet(t, 9.5)),
            pw.SizedBox(height: 10),
          ],
          if (!interim) ...[
            _heading('الإقرار بالتراضي والأهلية'),
            pw.Text(
              'يقر الشركاء الموقعون أدناه بأنهم كاملو الأهلية القانونية، وأنهم اطلعوا على جميع بنود هذا العقد وتراضوا عليها بإرادتهم الحرة، وأن التواقيع والطوابع الزمنية المثبتة أدناه صادرة عنهم.',
              style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 4),
            ),
            pw.SizedBox(height: 12),
            pw.Wrap(
              spacing: 12,
              runSpacing: 12,
              children: s.partners.map((p) {
                final so = s.signOffs[p.id];
                return _signBox(
                  title: p.name,
                  sub: so == null ? 'لم يوقع' : '${_dt.format(so.at)} · ${so.method.label}',
                  png: so?.signaturePng,
                );
              }).toList(),
            ),
            if (s.witnesses.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              _heading('الشهود'),
              pw.Wrap(
                spacing: 12,
                runSpacing: 12,
                children: s.witnesses
                    .map((w) => _signBox(
                          title: w.name,
                          sub: 'هوية ${w.nationalId} · ${w.internal ? 'من داخل الشركة' : 'من خارج الشركة'}',
                          png: w.signaturePng,
                        ))
                    .toList(),
              ),
            ],
          ] else
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 10),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _gold)),
              child: pw.Text(
                'هذا تقرير مرحلي يثبت ما تم التراضي عليه حتى تاريخه، ولا يُعد عقداً نهائياً قبل حسم جميع البنود وتوقيع الشركاء والشهود.',
                style: const pw.TextStyle(fontSize: 9.5),
              ),
            ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _bullet(String t, double size) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 4,
              height: 4,
              margin: const pw.EdgeInsets.only(top: 5, left: 6),
              decoration: const pw.BoxDecoration(color: _gold, shape: pw.BoxShape.circle),
            ),
            pw.Expanded(child: pw.Text(t, style: pw.TextStyle(fontSize: size))),
          ],
        ),
      );

  static pw.Widget _heading(String t) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8, top: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF4EEDC),
          border: pw.Border(right: pw.BorderSide(color: _gold, width: 3)),
        ),
        child: pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: _navy)),
      );

  static pw.Widget _kv(List<(String, String)> rows) => pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.6),
        columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(2)},
        children: rows
            .map((r) => pw.TableRow(children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(5),
                    color: const PdfColor.fromInt(0xFFF7F4EA),
                    child: pw.Text(r.$1, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(r.$2, style: const pw.TextStyle(fontSize: 10)),
                  ),
                ]))
            .toList(),
      );

  static pw.Widget _signBox({required String title, required String sub, String? png}) => pw.Container(
        width: 160,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
        child: pw.Column(
          children: [
            pw.SizedBox(
              height: 60,
              child: png == null
                  ? pw.SizedBox()
                  : pw.Image(pw.MemoryImage(base64Decode(png)), fit: pw.BoxFit.contain),
            ),
            pw.Divider(color: _line, height: 6),
            pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text(sub, style: const pw.TextStyle(fontSize: 7.5, color: _muted), textAlign: pw.TextAlign.center),
          ],
        ),
      );
}

