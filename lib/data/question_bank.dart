import '../models/questionnaire.dart';

/// بنك الأسئلة المبدئي لعقد تأسيس شركة في اليمن، وفق قانون الشركات التجارية رقم (22) لسنة 1997م وتعديلاته.
/// البنود L00 وL01 وF01 وA01 جوهرية: لا تُؤجَّل ولا تُحيَّد في عقد التأسيس المودع للشهر.
/// يمثل نواة قابلة للتوسع (المستهدف 150–300 بند) عبر شاشة إدارة البنود.
const List<BankQuestion> seedQuestionBank = [
  // ───────────── قانوني ─────────────
  BankQuestion(
    id: 'L00',
    category: ClauseCategory.legal,
    title: 'أغراض الشركة',
    clauseTemplate: 'غرض الشركة: {purpose}، ولها أن تمارس كل ما يتصل بهذه الأغراض أو يعين على تحقيقها في حدود القانون.',
    awareness:
        'الأغراض بند جوهري لا يُترك معلقاً في العقد المودع للشهر. هل تتفقون على أغراض الشركة كما أدخلتموها؟',
    quorum: QuorumRule.unanimous,
  ),
  BankQuestion(
    id: 'L01',
    category: ClauseCategory.legal,
    title: 'الشكل القانوني والقانون الحاكم',
    clauseTemplate:
        'تأسست الشركة بين الشركاء الموقعين أدناه في شكل {form}، وتخضع لأحكام قانون الشركات التجارية اليمني رقم (22) لسنة 1997م وتعديلاته والقانون المدني وقانون المرافعات والقوانين النافذة في الجمهورية اليمنية، ولهذا العقد ونظامه الأساسي. وتختص المحاكم التجارية اليمنية في مركز إدارة الشركة الرئيسي بنظر ما لا يُحل من نزاعات وفق آلية فض النزاعات في هذا العقد.',
    awareness:
        'الشكل القانوني يحدد حدود مسؤولية كل شريك: في ذات المسؤولية المحدودة تقتصر على الحصة، وفي التضامن تمتد إلى الأموال الخاصة. هل تتفقون على الشكل المختار وأثره؟',
    quorum: QuorumRule.unanimous,
  ),
  BankQuestion(
    id: 'L02',
    category: ClauseCategory.legal,
    title: 'مدة الشركة',
    clauseTemplate:
        'مدة الشركة {value} سنة تبدأ من تاريخ قيدها في السجل التجاري، وتتجدد تلقائياً لمدة مماثلة ما لم يقرر الشركاء خلاف ذلك قبل انتهائها بستة أشهر.',
    awareness:
        'تحديد المدة يحسم متى يحق لأي شريك المطالبة بالتصفية دون نزاع. ما المدة التي تناسب طبيعة نشاطكم؟',
    paramKind: ParamKind.number,
    paramLabel: 'مدة الشركة (بالسنوات)',
    defaultValue: 25,
  ),
  BankQuestion(
    id: 'L03',
    category: ClauseCategory.legal,
    title: 'حظر المنافسة',
    clauseTemplate:
        'يلتزم كل شريك بعدم ممارسة نشاط منافس لنشاط الشركة، مباشرة أو بواسطة الغير، طوال مدة الشراكة ولمدة {value} شهراً بعد تخارجه.',
    awareness:
        'كثير من النزاعات تبدأ حين يفتح أحد الشركاء نشاطاً موازياً. هل توافقون على حظر المنافسة ومدته بعد الخروج؟',
    paramKind: ParamKind.number,
    paramLabel: 'مدة الحظر بعد التخارج (بالأشهر)',
    defaultValue: 24,
  ),
  BankQuestion(
    id: 'L04',
    category: ClauseCategory.legal,
    title: 'السرية وحماية المعلومات',
    clauseTemplate:
        'يلتزم الشركاء بالمحافظة على سرية معلومات الشركة وبياناتها المالية والتجارية، ولا يجوز إفشاؤها للغير إلا بموافقة الشركاء أو بأمر من جهة مختصة.',
    awareness:
        'هل يشمل الالتزام بالسرية ما بعد خروج الشريك من الشركة؟ هذا البند يحمي أسرار العمل من التسرب.',
  ),
  BankQuestion(
    id: 'L05',
    category: ClauseCategory.legal,
    title: 'حق الأولوية عند بيع الحصص',
    clauseTemplate:
        'لا يجوز لأي شريك التنازل عن حصته أو جزء منها للغير قبل عرضها على باقي الشركاء، ولهم حق استردادها بنسبة حصصهم خلال {value} يوماً من تاريخ الإخطار.',
    awareness:
        'حق الأولوية يمنع دخول شريك غريب دون رضاكم. كم يوماً تحتاجون لدراسة العرض قبل أن يحق للشريك البيع للغير؟',
    quorum: QuorumRule.unanimous,
    paramKind: ParamKind.days,
    paramLabel: 'مهلة ممارسة حق الأولوية (بالأيام)',
    defaultValue: 30,
  ),
  BankQuestion(
    id: 'L06',
    category: ClauseCategory.legal,
    title: 'آلية فض النزاعات',
    clauseTemplate:
        'يُسوّى أي نزاع ينشأ بين الشركاء ودياً بالتفاوض المباشر خلال 14 يوماً، ثم بالوساطة خلال 30 يوماً، فإن تعذر ذلك يُحال إلى المركز اليمني للتوفيق والتحكيم ويكون حكمه نهائياً وملزماً.',
    awareness:
        'التحكيم أسرع وأكثر سرية من المحاكم. هل توافقون على هذا التدرج قبل اللجوء للتحكيم؟',
    quorum: QuorumRule.unanimous,
  ),
  BankQuestion(
    id: 'L07',
    category: ClauseCategory.legal,
    title: 'حجية الإشعارات الرقمية',
    clauseTemplate:
        'يُعتد بالإشعارات المرسلة عبر الرسائل النصية القصيرة (SMS) على الأرقام المسجلة للشركاء كوسيلة تبليغ رسمية منتجة لآثارها القانونية، تليها رسائل البريد الإلكتروني، ويُعد سجل الإرسال في المنصة دليلاً على التبليغ.',
    awareness:
        'اعتماد SMS كتبليغ رسمي يمنع أي شريك من إنكار استلام الإشعار لاحقاً. هل تتفقون على ذلك؟',
    quorum: QuorumRule.unanimous,
  ),
  BankQuestion(
    id: 'L08',
    category: ClauseCategory.legal,
    title: 'سيادة العقد الموثّق وحجية التوقيع',
    clauseTemplate:
        'هذا العقد بعد توثيقه وشهره بالسجل التجاري هو المرجع القانوني الأعلى بين الشركاء وفي مواجهة الغير، وتعد قواعد التشغيل في المنصة أداة لتنفيذه لا تعدله، ويسود نص العقد عند أي تعارض. ويُعد التوقيع والبصمة في المنصة توثيقاً داخلياً بين الشركاء يستكمل بالمصادقة الرسمية أمام الجهة المختصة.',
    awareness:
        'التوقيع الرقمي بينكم لا يغني عن المصادقة الرسمية والشهر لاكتساب الشخصية الاعتبارية. هل تتفقون على أن العقد الموثق يسود على قواعد التشغيل؟',
    quorum: QuorumRule.unanimous,
  ),
  BankQuestion(
    id: 'L09',
    category: ClauseCategory.legal,
    title: 'وفاة الشريك وانتقال الحصص',
    clauseTemplate:
        'تستمر الشركة في حال وفاة أحد الشركاء بين الباقين وورثة المتوفى، وتنتقل حصته إلى ورثته بموجب حصر الوراثة الشرعي، مع حق الأفضلية للشركاء الباقين في شرائها بتقويم عادل خلال {value} يوماً، ويختار الورثة ممثلاً واحداً عنهم لممارسة حقوق التصويت.',
    awareness:
        'في شركات التضامن والتوصية تنقضي الشركة بوفاة الشريك ما لم ينص العقد على استمرارها. هل تتفقون على الاستمرار وحق الأفضلية ومهلته؟',
    quorum: QuorumRule.unanimous,
    paramKind: ParamKind.days,
    paramLabel: 'مهلة حق الأفضلية للشركاء (بالأيام)',
    defaultValue: 60,
  ),

  // ───────────── مالي ─────────────
  BankQuestion(
    id: 'F01',
    category: ClauseCategory.financial,
    title: 'رأس المال وتوزيع الحصص',
    clauseTemplate:
        'حُدد رأس مال الشركة بمبلغ {capital}، موزعاً على الشركاء بحسب النسب المبينة في جدول الشركاء المرفق بهذا العقد.',
    awareness:
        'راجعوا جدول الحصص جيداً، فهو أساس توزيع الأرباح والخسائر والتصويت في كل القرارات القادمة.',
    quorum: QuorumRule.unanimous,
  ),
  BankQuestion(
    id: 'F02',
    category: ClauseCategory.financial,
    title: 'سقف الصرف اللحظي للمدير',
    clauseTemplate:
        'لا يجوز للشريك المدير اعتماد أي فاتورة أو سند صرف أو عملية شراء منفردة تتجاوز قيمتها {value} إلا بموافقة الشركاء الموثقة عبر المنصة.',
    awareness:
        'هذا السقف هو ما ستراقبه المنصة آلياً: أي عملية تتجاوزه تُجمَّد ويصلكم تنبيه للموافقة أو الرفض. ما الحد المناسب؟',
    effect: EffectType.financial,
    paramKind: ParamKind.money,
    paramLabel: 'الحد الأقصى للعملية الواحدة',
    defaultValue: 2000,
    rule: RuleTemplate(
      field: 'transaction.amount',
      fieldLabel: 'قيمة العملية الواحدة',
      op: ComparisonOp.gt,
      action: 'تجميد العملية وتنبيه الشركاء غير المديرين',
    ),
  ),
  BankQuestion(
    id: 'F03',
    category: ClauseCategory.financial,
    title: 'سقف الصرف الشهري للمدير',
    clauseTemplate:
        'لا يجوز أن يتجاوز إجمالي المصروفات التشغيلية التي يعتمدها الشريك المدير خلال الشهر الواحد مبلغ {value}، وما زاد عن ذلك يتطلب موافقة الشركاء.',
    awareness:
        'السقف الشهري يمنع تجزئة المصروفات الكبيرة إلى عمليات صغيرة للالتفاف على السقف اللحظي.',
    effect: EffectType.financial,
    paramKind: ParamKind.money,
    paramLabel: 'الحد الأقصى الشهري',
    defaultValue: 10000,
    rule: RuleTemplate(
      field: 'monthly.expenses',
      fieldLabel: 'إجمالي مصروفات الشهر',
      op: ComparisonOp.gt,
      action: 'تجميد العمليات الجديدة وتنبيه الشركاء',
    ),
  ),
  BankQuestion(
    id: 'F04',
    category: ClauseCategory.financial,
    title: 'حظر السلف الشخصية',
    clauseTemplate:
        'يُحظر على أي شريك أو مدير سحب سلف شخصية من أموال الشركة أو تحميلها نفقات شخصية دون موافقة صريحة ومسبقة من الشركاء، وتُعد أي عملية مخالفة خرقاً لهذا العقد.',
    awareness:
        'خلط أموال الشركة بالأموال الشخصية من أشهر أسباب الخلاف. هل تمنعون السلف منعاً تاماً دون موافقة؟',
    effect: EffectType.financial,
    rule: RuleTemplate(
      field: 'transaction.type=personal_advance',
      fieldLabel: 'عملية سلفة شخصية',
      op: ComparisonOp.gt,
      action: 'رفض تلقائي وتسجيل خرق في تقرير الحوكمة',
    ),
  ),
  BankQuestion(
    id: 'F05',
    category: ClauseCategory.financial,
    title: 'توزيع الأرباح',
    clauseTemplate:
        'تُوزع الأرباح الصافية سنوياً على الشركاء بنسبة حصصهم في رأس المال، بعد اقتطاع {value}% احتياطياً قانونياً.',
    awareness:
        'هل توزع الأرباح كاملة أم يحتفظ بجزء منها لتوسعة الشركة؟ حددوا نسبة الاحتياطي.',
    paramKind: ParamKind.percent,
    paramLabel: 'نسبة الاحتياطي من صافي الربح',
    defaultValue: 10,
  ),
  BankQuestion(
    id: 'F06',
    category: ClauseCategory.financial,
    title: 'إنذار الخسائر الجسيمة',
    clauseTemplate:
        'إذا بلغت الخسائر المتراكمة {value}% من رأس المال، تلتزم الإدارة بدعوة الشركاء لاجتماع طارئ خلال 15 يوماً لتقرير استمرار الشركة أو حلها.',
    awareness:
        'المنصة سترصد هذه النسبة من البيانات المحاسبية وتطلق الإنذار تلقائياً. ما النسبة التي ترونها حداً للخطر؟',
    quorum: QuorumRule.unanimous,
    effect: EffectType.financial,
    paramKind: ParamKind.percent,
    paramLabel: 'نسبة الخسائر من رأس المال',
    defaultValue: 50,
    rule: RuleTemplate(
      field: 'losses.ratio',
      fieldLabel: 'نسبة الخسائر المتراكمة',
      op: ComparisonOp.gte,
      action: 'إشعار ملزم بدعوة الشركاء لاجتماع طارئ',
    ),
  ),
  BankQuestion(
    id: 'F07',
    category: ClauseCategory.financial,
    title: 'الاعتماد الثنائي للعقود الكبيرة',
    clauseTemplate:
        'يُشترط توقيع شريكين على الأقل لأي عقد أو التزام مالي تتجاوز قيمته {value}.',
    awareness:
        'العقود طويلة الأجل تُلزم الشركة لسنوات. هل تشترطون توقيعاً ثانياً فوق حد معين؟',
    effect: EffectType.financial,
    paramKind: ParamKind.money,
    paramLabel: 'حد العقد الذي يتطلب توقيعين',
    defaultValue: 10000,
    rule: RuleTemplate(
      field: 'contract.value',
      fieldLabel: 'قيمة العقد أو الالتزام',
      op: ComparisonOp.gt,
      action: 'طلب اعتماد من شريك ثانٍ',
    ),
  ),
  BankQuestion(
    id: 'F08',
    category: ClauseCategory.financial,
    title: 'الاطلاع على الدفاتر',
    clauseTemplate:
        'يحق لكل شريك الاطلاع على دفاتر الشركة وقوائمها المالية في أي وقت عبر المنصة، وتلتزم الإدارة بإصدار تقرير مالي كل {value} يوماً.',
    awareness:
        'الشفافية المالية تمنع سوء الظن. كل كم يوماً تريدون تقريراً مالياً؟',
    paramKind: ParamKind.days,
    paramLabel: 'دورية التقرير المالي (بالأيام)',
    defaultValue: 30,
  ),

  // ───────────── إداري ─────────────
  BankQuestion(
    id: 'A01',
    category: ClauseCategory.administrative,
    title: 'تعيين المدير وصلاحياته',
    clauseTemplate:
        'يتولى إدارة الشركة مدير يعينه الشركاء، ويمارس الأعمال اليومية في حدود الصلاحيات والسقوف المالية المحددة في هذا العقد، ولا يجوز له تجاوزها إلا بقرار من الشركاء.',
    awareness:
        'فصل الصلاحيات بين المدير والشركاء يحمي الشريك غير المدير. هل تتفقون على أن المدير مقيد بالسقوف المحددة؟',
  ),
  BankQuestion(
    id: 'A02',
    category: ClauseCategory.administrative,
    title: 'راتب المدير وتعديله',
    clauseTemplate:
        'يحدد راتب الشريك المدير بقرار من الشركاء، ولا يجوز له تعديل راتبه أو مزاياه بأي صورة دون موافقة الشركاء الموثقة.',
    awareness:
        'هل يتقاضى الشريك المدير راتباً إضافة إلى أرباحه؟ ومن يملك حق تعديله؟',
    effect: EffectType.financial,
    rule: RuleTemplate(
      field: 'payroll.manager_change',
      fieldLabel: 'تعديل راتب المدير',
      op: ComparisonOp.gt,
      action: 'تجميد التعديل وطلب موافقة الشركاء',
    ),
  ),
  BankQuestion(
    id: 'A03',
    category: ClauseCategory.administrative,
    title: 'توظيف الأقارب',
    clauseTemplate:
        'لا يجوز للمدير أو لأي شريك تعيين أقاربه حتى الدرجة الرابعة في الشركة إلا بموافقة باقي الشركاء.',
    awareness:
        'تضارب المصالح في التوظيف يسبب احتكاكاً دائماً. هل تريدون اشتراط الموافقة؟',
  ),
  BankQuestion(
    id: 'A04',
    category: ClauseCategory.administrative,
    title: 'نصاب القرارات العادية',
    clauseTemplate:
        'تصدر قرارات الشركاء العادية بأغلبية تمثل أكثر من نصف رأس المال، أما تعديل العقد أو زيادة رأس المال أو إدخال شريك جديد فيتطلب موافقة الشركاء بالإجماع.',
    awareness:
        'حسم النصاب مسبقاً يمنع جمود التصويت لاحقاً. هل توافقون على التفرقة بين القرارات العادية والجوهرية؟',
    quorum: QuorumRule.unanimous,
  ),
  BankQuestion(
    id: 'A05',
    category: ClauseCategory.administrative,
    title: 'كسر الجمود في التصويت',
    clauseTemplate:
        'إذا تعادلت الأصوات أو تعذر اكتمال النصاب مرتين متتاليتين في قرار جوهري، يُفعّل نظام العرض المغلق، بحيث يقدم أحد الشركاء عرضاً لشراء حصة الآخر، ويكون للآخر خلال {value} ساعة أن يبيع أو يشتري بالسعر نفسه.',
    awareness:
        'هذا البند يضمن ألا تتوقف الشركة إذا اختلف الشركاء اختلافاً لا حل له. هل تقبلونه كحل أخير؟',
    quorum: QuorumRule.unanimous,
    paramKind: ParamKind.number,
    paramLabel: 'مهلة الرد على العرض (بالساعات)',
    defaultValue: 72,
  ),
  BankQuestion(
    id: 'A06',
    category: ClauseCategory.administrative,
    title: 'القرارات الجوهرية والنصاب المشدد',
    clauseTemplate:
        'لا يجوز تعديل عقد الشركة أو نظامها الأساسي أو زيادة رأس المال أو تخفيضه أو حل الشركة أو دمجها إلا بموافقة شركاء يملكون 75% من رأس المال على الأقل، ولا يجوز أي تعديل يزيد الأعباء المالية على الشركاء إلا بإجماعهم. ولا يصوّت الشريك أو المدير على قرار له فيه مصلحة مباشرة أو غير مباشرة، ويلتزم بالإفصاح عنها.',
    awareness:
        'هذه حماية قانونية للأقلية: 75% للقرارات الجوهرية، والإجماع لزيادة الأعباء، ومنع التصويت عند تعارض المصالح. هل تتفقون عليها؟',
    quorum: QuorumRule.unanimous,
  ),

  // ───────────── بنود خاصة بكل شريك ─────────────
  BankQuestion(
    id: 'P01',
    category: ClauseCategory.financial,
    scope: ClauseScope.private,
    title: 'إقرار سداد الحصة',
    clauseTemplate:
        'يقر الشريك {partner} بالتزامه بسداد قيمة حصته في رأس المال نقداً خلال {value} يوماً من تاريخ التوقيع.',
    awareness:
        'هذا إقرار شخصي لكل شريك، ولا يُعتمد إلا بموافقته هو نفسه.',
    paramKind: ParamKind.days,
    paramLabel: 'مهلة السداد (بالأيام)',
    defaultValue: 30,
  ),
  BankQuestion(
    id: 'P02',
    category: ClauseCategory.legal,
    scope: ClauseScope.private,
    title: 'تفضيلات الإشعار',
    clauseTemplate:
        'يوافق الشريك {partner} على تلقي الإشعارات الرسمية للشركة على رقم جواله وبريده المسجلين، ولا يجوز تعديل هذا الخيار لاحقاً إلا بموافقة الشركاء إذا ارتبط بحقوقه الرقابية.',
    awareness:
        'تحديد وسيلة التبليغ لكل شريك يحفظ حجية الإشعارات. هل توافق على استلام الإشعارات؟',
  ),
];
