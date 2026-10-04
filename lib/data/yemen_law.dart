/// المحتوى القانوني اليمني المعتمد في التطبيق، من وثائق "ملف الاضافات":
/// - أقسام الشركات التجارية المشروعة وشروط تأسيسها (قانون الشركات التجارية رقم 22 لسنة 1997م وتعديلاته)
/// - الحسم وفق القانون اليمني
/// - دليل الاستخدام والامتثال
///
/// هذه القيم إرشادية مستمدة من الوثائق، والمرجع النهائي هو القانون النافذ ولوائح الوزارة المختصة.
library;

/// الأشكال القانونية الستة المنصوص عليها حصراً (المادة 9)، مع تقسيم المساهمة إلى عامة ومقفلة
enum CompanyForm { llc, generalPartnership, limitedPartnership, jointVenture, closedJointStock, publicJointStock, partnershipLimitedByShares }

/// صفة الشريك في شركات التوصية
enum PartnerClass { general, limited }

extension PartnerClassX on PartnerClass {
  String get label => this == PartnerClass.general ? 'شريك متضامن' : 'شريك موصٍ';
}

class CompanyFormSpec {
  final CompanyForm form;
  final String label;
  final bool personsCompany; // شركات أشخاص أو أموال
  final String definition;
  final String liability;
  final int minPartners;
  final int? maxPartners;
  final double? minCapitalYer;
  final double? minShareValueYer;
  final String licensing;
  final bool legalPersonality;

  /// شركات التوصية: فئتان من الشركاء (متضامن وموصٍ)
  final bool twoClasses;

  /// الشريك المتضامن يشترط أن يكون يمني الجنسية كامل الأهلية (18 سنة)
  final bool generalPartnerYemeni;

  /// يتطلب مجلس إدارة (من 3 إلى 11 عضواً) وجمعية تأسيسية
  final bool board;
  final List<String> documents;
  final List<String> notes;

  /// أثر وفاة الشريك
  final String onDeath;

  const CompanyFormSpec({
    required this.form,
    required this.label,
    required this.personsCompany,
    required this.definition,
    required this.liability,
    required this.minPartners,
    this.maxPartners,
    this.minCapitalYer,
    this.minShareValueYer,
    required this.licensing,
    this.legalPersonality = true,
    this.twoClasses = false,
    this.generalPartnerYemeni = false,
    this.board = false,
    required this.documents,
    this.notes = const [],
    required this.onDeath,
  });

  String get category => personsCompany ? 'شركات الأشخاص' : 'شركات الأموال';
}

const _commonDocs = [
  'إفادة حجز الاسم التجاري',
  'أصل عقد التأسيس والنظام الأساسي موقّعين',
  'صور الهويات السارية للشركاء والمدير',
];

const kCompanyForms = <CompanyFormSpec>[
  CompanyFormSpec(
    form: CompanyForm.llc,
    label: 'شركة ذات مسؤولية محدودة',
    personsCompany: false,
    definition: 'شركة لا يقل عدد شركائها عن اثنين ولا يزيد على ثلاثين، ورأسمالها مقسم إلى حصص لا إلى أسهم قابلة للتداول.',
    liability: 'مسؤولية كل شريك محدودة بحصته في رأس المال.',
    minPartners: 2,
    maxPartners: 30,
    minCapitalYer: 3000000,
    minShareValueYer: 5000,
    licensing: 'قرار ترخيص من وزير الصناعة والتجارة بناءً على طلب يُرفع لمراقب الشركات',
    documents: [
      ..._commonDocs,
      'شهادة بنكية بإيداع رأس المال النقدي كاملاً باسم الشركة تحت التأسيس',
      'محضر اتفاق تعيين المدير العام والمحاسب القانوني',
    ],
    notes: [
      'يُدفع رأس المال النقدي كاملاً في مصرف معتمد باليمن قبل الترخيص.',
      'تُوقَّع الاستمارة وعقد التأسيس والنظام الأساسي أمام مراقب الشركات أو المحكمة المختصة.',
    ],
    onDeath: 'تنتقل حصة الشريك المتوفى إلى ورثته بموجب حصر الوراثة، مع حق الأفضلية للشركاء الباقين بتقويم عادل إن نص النظام الأساسي على ذلك، ويمثّل الورثة ممثل واحد في التصويت.',
  ),
  CompanyFormSpec(
    form: CompanyForm.generalPartnership,
    label: 'شركة تضامن',
    personsCompany: true,
    definition: 'شركة تقوم على الاعتبار الشخصي والثقة المتبادلة بين الشركاء.',
    liability: 'جميع الشركاء مسؤولون شخصياً وبالتضامن في أموالهم الخاصة عن ديون الشركة والتزاماتها.',
    minPartners: 2,
    minShareValueYer: 5000,
    licensing: 'مصادقة العقد أمام مراقب الشركات أو المحكمة التجارية أو مدير مكتب الوزارة بالمحافظة، وقيده بالسجل التجاري خلال شهر من توقيعه',
    generalPartnerYemeni: true,
    documents: _commonDocs,
    notes: ['يُشترط في الشريك المتضامن أن يكون يمني الجنسية بالغاً 18 سنة كامل الأهلية.'],
    onDeath: 'تنقضي الشركة بوفاة أحد الشركاء ما لم ينص عقد التأسيس صراحةً على استمرارها بين الباقين أو مع ورثة المتوفى.',
  ),
  CompanyFormSpec(
    form: CompanyForm.limitedPartnership,
    label: 'شركة توصية بسيطة',
    personsCompany: true,
    definition: 'شركة من فئتين: شركاء متضامنون يديرونها، وشركاء موصون يقدمون المال فقط.',
    liability: 'المتضامنون مسؤولون في أموالهم الخاصة، والموصون في حدود ما قدموه، ولا يتدخلون في الإدارة الخارجية.',
    minPartners: 2,
    minShareValueYer: 5000,
    licensing: 'مصادقة العقد وقيده بالسجل التجاري كشركات الأشخاص',
    twoClasses: true,
    generalPartnerYemeni: true,
    documents: _commonDocs,
    notes: ['للشركاء المتضامنين دون غيرهم حق الإدارة.'],
    onDeath: 'تنقضي الشركة بوفاة شريك متضامن ما لم ينص العقد على استمرارها، وتنتقل حصة الشريك الموصي لورثته.',
  ),
  CompanyFormSpec(
    form: CompanyForm.jointVenture,
    label: 'شركة محاصة',
    personsCompany: true,
    definition: 'شركة مستترة ينحصر كيانها بين المتعاقدين لصفقة أو صفقات محدودة.',
    liability: 'كل شريك يتعامل مع الغير باسمه ويُسأل عن التزاماته.',
    minPartners: 2,
    licensing: 'لا تخضع لإجراءات الشهر والتسجيل التجاري',
    legalPersonality: false,
    documents: ['عقد المحاصة الموقّع بين الشركاء'],
    notes: ['لا تتمتع بالشخصية الاعتبارية، ولا تُسجَّل في السجل التجاري.'],
    onDeath: 'تخضع لما يتفق عليه الشركاء في عقد المحاصة.',
  ),
  CompanyFormSpec(
    form: CompanyForm.closedJointStock,
    label: 'شركة مساهمة مقفلة',
    personsCompany: false,
    definition: 'رأسمالها مقسم إلى أسهم متساوية القيمة، ولا تطرح أسهمها للاكتتاب العام.',
    liability: 'لا يُسأل المساهم إلا بقدر قيمة أسهمه.',
    minPartners: 5,
    minCapitalYer: 15000000,
    minShareValueYer: 10000,
    licensing: 'قرار ترخيص من وزير الصناعة والتجارة',
    board: true,
    documents: [
      ..._commonDocs,
      'شهادة بنكية بإيداع رأس المال كاملاً عند التأسيس',
      'محضر الجمعية العمومية التأسيسية وتشكيل مجلس الإدارة الأول وتعيين المحاسب القانوني',
    ],
    notes: ['يُدفع رأس المال كاملاً عند التأسيس.', 'مجلس إدارة من 3 إلى 11 عضواً.'],
    onDeath: 'تنتقل الأسهم إلى الورثة وفق حصر الوراثة وأحكام النظام الأساسي.',
  ),
  CompanyFormSpec(
    form: CompanyForm.publicJointStock,
    label: 'شركة مساهمة عامة',
    personsCompany: false,
    definition: 'شركة مساهمة تطرح أسهمها للاكتتاب العام وفق الضوابط الرسمية.',
    liability: 'لا يُسأل المساهم إلا بقدر قيمة أسهمه.',
    minPartners: 5,
    minCapitalYer: 50000000,
    minShareValueYer: 10000,
    licensing: 'قرار ترخيص من رئيس مجلس الوزراء',
    board: true,
    documents: [
      ..._commonDocs,
      'شهادة بنكية بدفع 25% على الأقل عند الاكتتاب',
      'محضر الجمعية العمومية التأسيسية وتشكيل مجلس الإدارة الأول وتعيين المحاسب القانوني',
    ],
    notes: ['يُدفع 25% على الأقل عند الاكتتاب ويُطرح الباقي للجمهور.', 'مجلس إدارة من 3 إلى 11 عضواً.'],
    onDeath: 'تنتقل الأسهم إلى الورثة وفق حصر الوراثة وأحكام النظام الأساسي.',
  ),
  CompanyFormSpec(
    form: CompanyForm.partnershipLimitedByShares,
    label: 'شركة توصية بالأسهم',
    personsCompany: false,
    definition: 'شركة من فئتين: شركاء متضامنون، وشركاء مساهمون ينقسم رأسمالهم إلى أسهم.',
    liability: 'المتضامنون مسؤولون في جميع أموالهم، والمساهمون في حدود حصصهم.',
    minPartners: 2,
    minShareValueYer: 10000,
    licensing: 'قرار ترخيص من وزير الصناعة والتجارة',
    twoClasses: true,
    generalPartnerYemeni: true,
    documents: _commonDocs,
    onDeath: 'تنقضي بوفاة شريك متضامن ما لم ينص العقد على استمرارها، وتنتقل أسهم المساهمين لورثتهم.',
  ),
];

CompanyFormSpec formSpec(CompanyForm f) => kCompanyForms.firstWhere((s) => s.form == f);

/// الشكل القانوني من اسمه المخزّن في الشركة (الشركات القديمة تبقى ذات مسؤولية محدودة افتراضياً)
CompanyFormSpec formSpecOf(String? label) =>
    kCompanyForms.where((s) => s.label == label).firstOrNull ?? formSpec(CompanyForm.llc);

/// تحقق شروط التأسيس حسب الشكل القانوني. القيم بالريال اليمني، وعملة العقد بالدولار أو الريال السعودي،
/// فيلزم سعر صرف معتمد للتحقق من الحد الأدنى لرأس المال.
List<String> formViolations(
  CompanyFormSpec f, {
  required int partners,
  required int generalPartners,
  required int limitedPartners,
  required int nonYemeniGeneral,
  required int minorGeneral,
  required double capital,
  double? yerRate,
}) {
  final out = <String>[];
  if (partners < f.minPartners) out.add('${f.label} تتطلب ${f.minPartners} شركاء على الأقل');
  if (f.maxPartners != null && partners > f.maxPartners!) out.add('${f.label} لا تتجاوز ${f.maxPartners} شريكاً');
  if (f.twoClasses && (generalPartners == 0 || limitedPartners == 0)) {
    out.add('${f.label} تتطلب شريكاً متضامناً واحداً على الأقل وشريكاً ${f.form == CompanyForm.limitedPartnership ? 'موصياً' : 'مساهماً'} واحداً على الأقل');
  }
  if (f.generalPartnerYemeni && nonYemeniGeneral > 0) out.add('الشريك المتضامن يجب أن يكون يمني الجنسية');
  if (f.generalPartnerYemeni && minorGeneral > 0) out.add('الشريك المتضامن يجب أن يكون بالغاً 18 سنة كامل الأهلية');
  if (f.minCapitalYer != null && yerRate != null && yerRate > 0 && capital * yerRate + 1e-6 < f.minCapitalYer!) {
    out.add('رأس المال يعادل ${(capital * yerRate).toStringAsFixed(0)} ريالاً يمنياً، والحد الأدنى ${f.minCapitalYer!.toStringAsFixed(0)}');
  }
  return out;
}

// ───────────── الحسم وفق القانون اليمني ─────────────

/// النصاب المشدد للقرارات الجوهرية: تعديل العقد أو النظام، وزيادة رأس المال أو تخفيضه، والحل والدمج
const kSupermajority = 75.0;

/// البنود الجوهرية التي لا يجوز تأجيلها أو تحييدها في عقد التأسيس المودع للشهر
const kEssentialClauses = {'L01', 'L00', 'F01', 'A01'};

const kContractSupremacy =
    'العقد الموثّق والمشهر بالسجل التجاري هو المرجع القانوني الأعلى. قواعد التشغيل في المنصة أداة لتنفيذه، وعند أي تعارض يسود نص العقد.';

const kSignatureNotice =
    'التوقيع والبصمة في المنصة توثيق داخلي بين الشركاء. لإنتاج الأثر القانوني الكامل يلزم إثبات التواقيع أمام مراقب الشركات أو مدير مكتب الوزارة بالمحافظة أو المحكمة المختصة (المادتان 165 و208)، ويُتاح التوقيع الورقي الحضوري لمن لا يملك وسيلة رقمية.';

/// خطوات الشهر والاستيفاء القانوني (المحور الرابع من دليل الامتثال)
class ComplianceStepSpec {
  final String id;
  final String title;
  final String action;
  final String authority;
  final String effect;
  const ComplianceStepSpec(this.id, this.title, this.action, this.authority, this.effect);
}

const kComplianceSteps = <ComplianceStepSpec>[
  ComplianceStepSpec('bank', 'حجز الاسم والشهادة البنكية', 'حجز الاسم التجاري وإيداع رأس المال النقدي لدى بنك معتمد',
      'وزارة الصناعة والتجارة / البنك المعتمد', 'إصدار الشهادة البنكية واستكمال ملف التأسيس'),
  ComplianceStepSpec('notarize', 'المصادقة الرسمية على التواقيع', 'المصادقة على توقيعات الشركاء في عقد التأسيس والنظام الأساسي',
      'الإدارة العامة للشركات / موثق المحكمة التجارية', 'اكتمال الشكلية الرسمية لعقد التأسيس'),
  ComplianceStepSpec('license', 'الترخيص والقيد', 'إصدار قرار الترخيص وقيد الشركة بالسجل التجاري', 'الوزارة المختصة / السجل التجاري',
      'اكتساب الشركة الشخصية الاعتبارية المستقلة'),
  ComplianceStepSpec('publish', 'النشر والإشهار', 'نشر عقد التأسيس والنظام الأساسي في الجريدة الرسمية وصحيفة التجارة',
      'الجريدة الرسمية / صحيفة الوزارة', 'نفاذ تصرفات الشركة في مواجهة الغير'),
  ComplianceStepSpec('cards', 'البطاقات والتراخيص', 'استخراج البطاقة الضريبية والتأمينية وتجهيز مقر العمل',
      'مصلحة الضرائب / التأمينات الاجتماعية', 'بدء الممارسة الميدانية والتوظيف القانوني'),
];

/// تنبيهات ختامية من دليل الامتثال
const kComplianceWarnings = [
  'يُحظر تعديل أوزان التصويت أو حصص الشركاء مباشرة من قاعدة البيانات؛ أي تعديل باطل ما لم يُعتمد بقرار الشركاء ويُشهر بالسجل التجاري.',
  'إهمال شهر الشركة أو عدم ذكر صفة المسؤولية المحدودة في المطبوعات والمعاملات يجعل المديرين والشركاء مسؤولين شخصياً وبالتضامن تجاه الغير.',
  'يُحتفظ بسجل تدقيق لكل عملية تصويت بوقتها ومرجعها لاستخدامه دليلاً أمام القضاء التجاري اليمني.',
  'الميثاق العائلي ملزم بين أفراد العائلة، ولا يسري على الشركة والغير إلا بإدماج أحكامه في النظام الأساسي المشهر.',
  'يخضع توظيف أفراد العائلة لقانون العمل رقم (5) لسنة 1995م: عقد مكتوب، ووصف وظيفي، وأجر بمستوى السوق.',
];

/// أقسام دليل الاستخدام والامتثال المختصرة للعرض داخل التطبيق
const kGuideSections = <(String, List<String>)>[
  ('اختيار الكيان القانوني', [
    'تبدأ رحلة التأسيس باختيار الشكل القانوني، فيطبق التطبيق شروطه: عدد الشركاء، والحد الأدنى لرأس المال، وفئات الشركاء.',
    'كل كيان لا يتخذ أحد الأشكال المنصوص عليها حصراً باطل، ويتحمل المتعاقدون باسمه مسؤولية شخصية وتضامنية.',
  ]),
  ('الشركاء والأهلية', [
    'تُرفع الهويات السارية لجميع الشركاء.',
    'الشريك القاصر أو ناقص الأهلية يمثّله وليّه الشرعي أو وصيّه المأذون قضائياً، مع إرفاق حكم الوصاية.',
  ]),
  ('التصويت والنصاب', [
    'الأصوات مرجّحة بنسبة الملكية في رأس المال.',
    'المحايد يُحتسب في نصاب الحضور ولا يُضاف للموافقة، وعدم التصويت ليس موافقة.',
    'القرارات الجوهرية (تعديل العقد أو النظام، تغيير رأس المال، الحل أو الدمج) تتطلب 75% من رأس المال على الأقل.',
    'القرارات التي تزيد الأعباء المالية على الشركاء تتطلب إجماعهم.',
  ]),
  ('الجمود وفض النزاعات', [
    'يُعد الجمود قائماً بتعذر الأغلبية في جولتين متتاليتين حول قرار جوهري، فتُفتح تذكرة نزاع.',
    'التدرج: تسوية ودية ووساطة، ثم التحكيم التجاري وفق قانون التحكيم اليمني رقم (22) لسنة 1992م عند وجود شرط تحكيم، ثم القضاء التجاري بمركز الشركة.',
  ]),
  ('البنود الجوهرية', [
    'لا يجوز إصدار عقد تأسيس نهائي وفيه بنود جوهرية مؤجلة أو محيّدة، مثل الشكل القانوني والأغراض ورأس المال والحصص والإدارة.',
  ]),
  ('تعارض المصالح', [
    'يلتزم الشريك أو المدير بالإفصاح عن أي مصلحة في التعامل، ولا يصوّت على القرارات المتعلقة به.',
  ]),
];
