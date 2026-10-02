import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/company.dart';
import '../models/dispute.dart';

/// تقارير PDF للتدقيق والتحكيم:
/// - تقرير سجل التدقيق (P15 / A18)
/// - ملف القضية للتحكيم (P19): الخط الزمني للنزاع وسجل التدقيق والأدلة، مثبَّت ببصمة SHA-256
class ReportPdf {
  ReportPdf._();

  static const _navy = PdfColor.fromInt(0xFF0F1B2E);
  static const _gold = PdfColor.fromInt(0xFFA3811C);
  static const _muted = PdfColor.fromInt(0xFF5B6B82);
  static const _line = PdfColor.fromInt(0xFFD9D2BE);
  static final _dt = DateFormat('yyyy/MM/dd HH:mm');

  /// المحتوى القانوني لملف القضية بترتيب ثابت؛ بصمته مرجع سلامة المستند
  static String caseContent(Company c, Dispute d, List<AuditEvent> audit) => jsonEncode({
        'company': [c.id, c.legalName, c.contractVersion],
        'dispute': {...d.toJson(), 'caseFileHash': null},
        'audit': audit.map((e) => e.toJson()).toList(),
      });

  static String caseHash(Company c, Dispute d, List<AuditEvent> audit) =>
      sha256.convert(utf8.encode(caseContent(c, d, audit))).toString();

  static Future<void> shareCaseFile(Company c, Dispute d, List<AuditEvent> audit, String hash) => Printing.layoutPdf(
        name: 'ملف_قضية_${d.id}.pdf',
        onLayout: (f) => build(
          f,
          title: 'ملف قضية تحكيم',
          subtitle: '${c.legalName} · التذكرة ${d.id}',
          hash: hash,
          sections: [
            ('بيانات النزاع', [
              ('المحفز', d.trigger.label),
              ('موضوع النزاع', d.issue),
              ('إصدار العقد عند الفتح', '${d.contractVersion}'),
              ('تاريخ الفتح', _dt.format(d.openedAt.toLocal())),
              ('المرحلة', d.stage.label),
              ('جهة الوساطة', d.mediator ?? '—'),
              ('مركز التحكيم', d.arbitrationCenter ?? '—'),
              ('الأطراف', d.parties.map((p) => c.members.where((m) => m.id == p).firstOrNull?.name ?? p).join('، ')),
            ]),
            ('الخط الزمني للنزاع', [
              for (final e in d.entries)
                ('${_dt.format(e.at.toLocal())} · ${e.stage.label} · ${e.kind.label}',
                    '${e.authorName}: ${e.text}${e.evidenceRef == null ? '' : ' (${e.evidenceRef})'}'),
            ]),
            ('سجل التدقيق', [
              for (final e in audit)
                ('${_dt.format(e.at.toLocal())} · ${e.actorType.label}',
                    '${e.actorName.isEmpty ? '' : '${e.actorName}: '}${e.action}${e.result.isEmpty ? '' : ' · ${e.result}'}'),
            ]),
          ],
        ),
      );

  static Future<void> shareAudit(Company c, List<AuditEvent> events, {String filter = 'كل الأحداث'}) =>
      Printing.layoutPdf(
        name: 'سجل_التدقيق_${c.legalName}.pdf',
        onLayout: (f) => build(
          f,
          title: 'تقرير سجل التدقيق',
          subtitle: '${c.legalName} · $filter · ${events.length} حدث',
          hash: sha256.convert(utf8.encode(jsonEncode(events.map((e) => e.toJson()).toList()))).toString(),
          sections: [
            ('الأحداث', [
              for (final e in events)
                ('${_dt.format(e.at.toLocal())} · ${e.actorType.label}${e.contractVersion == null ? '' : ' · الإصدار ${e.contractVersion}'}',
                    '${e.actorName.isEmpty ? '' : '${e.actorName}: '}${e.action}${e.result.isEmpty ? '' : ' · ${e.result}'}'
                        '${e.evidenceRef == null ? '' : ' · الدليل: ${e.evidenceRef}'}'),
            ]),
          ],
        ),
      );

  static Future<Uint8List> build(PdfPageFormat format,
      {required String title,
      required String subtitle,
      required String hash,
      required List<(String, List<(String, String)>)> sections}) async {
    final regular = await PdfGoogleFonts.notoNaskhArabicRegular();
    final bold = await PdfGoogleFonts.notoNaskhArabicBold();
    final latin = await PdfGoogleFonts.notoSansRegular();
    final doc = pw.Document(
      title: title,
      author: 'ميثاق',
      theme: pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [latin]),
    );
    doc.addPage(pw.MultiPage(
      pageFormat: format,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 46),
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        margin: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _gold, width: 1.2))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('ميثاق · نظام العقود والحوكمة الذكي', style: const pw.TextStyle(color: _muted, fontSize: 8)),
          pw.Text(_dt.format(DateTime.now()), style: const pw.TextStyle(color: _muted, fontSize: 8)),
        ]),
      ),
      footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('مرجع سلامة المستند (SHA-256): $hash', style: const pw.TextStyle(color: _muted, fontSize: 6.5)),
        pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(color: _muted, fontSize: 8)),
      ]),
      build: (ctx) => [
        pw.Center(
            child: pw.Text(title, style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: _navy))),
        pw.Center(child: pw.Text(subtitle, style: const pw.TextStyle(fontSize: 11, color: _gold))),
        pw.SizedBox(height: 14),
        for (final (name, rows) in sections) ...[
          pw.Text(name, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _navy)),
          pw.SizedBox(height: 4),
          if (rows.isEmpty) pw.Text('لا توجد سجلات.', style: const pw.TextStyle(color: _muted, fontSize: 9)),
          for (final (k, v) in rows)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5))),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(k, style: const pw.TextStyle(color: _muted, fontSize: 8)),
                pw.Text(v, style: const pw.TextStyle(fontSize: 9.5)),
              ]),
            ),
          pw.SizedBox(height: 12),
        ],
      ],
    ));
    return doc.save();
  }
}
