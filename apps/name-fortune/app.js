/* 知命阁 · 姓名测算（仅供娱乐） */
(() => {
'use strict';

/* ===================== 基础数据 ===================== */
const GAN = ['甲','乙','丙','丁','戊','己','庚','辛','壬','癸'];
const ZHI = ['子','丑','寅','卯','辰','巳','午','未','申','酉','戌','亥'];
const GAN_WX = ['木','木','火','火','土','土','金','金','水','水'];
const ZHI_WX = ['水','土','木','木','土','火','火','土','金','金','土','水'];
const WX = ['金','木','水','火','土'];
const ZHI_HOUR = ['子','丑','寅','卯','辰','巳','午','未','申','酉','戌','亥'];

/* 姓氏渊源（简述，原创文案） */
const SURNAMES = {
  '王':'多出自姬姓，为周朝王族之后，因是"王者之后"而得姓。太原王氏、琅琊王氏自魏晋起便是天下望族，名相名士辈出。',
  '李':'出自嬴姓，上古贤臣皋陶曾任"理官"，后人以官为氏，改"理"为"李"。至唐代成为国姓，陇西李氏显赫一时。',
  '张':'出自姬姓。相传黄帝之孙挥善制弓箭，任"弓正"之职，遂以"张"为姓。清河张氏为古代著名郡望。',
  '刘':'最早出自祁姓，尧帝后裔受封于刘邑而得姓。汉朝四百年基业使刘姓遍布天下，彭城刘氏尤为兴盛。',
  '陈':'出自妫姓，周武王封舜帝后人胡公满于陈国，子孙以国为姓。颍川陈氏自东汉名士陈寔起声望极高。',
  '杨':'出自姬姓，周代晋国公族受封于杨邑，以邑为氏。弘农杨氏在汉唐之间累世公卿，有"四世三公"美称。',
  '黄':'出自嬴姓，上古黄国（今河南潢川一带）国人以国为姓。江夏黄氏为汉代著名望族，孝子黄香即出此族。',
  '赵':'出自嬴姓，造父为周穆王驾车有功，受封赵城而得姓。战国赵国与宋朝皇族让赵姓位列《百家姓》之首。',
  '吴':'出自姬姓，周太王长子泰伯让位奔吴，建吴国，后人以国为姓。延陵吴氏以"季札挂剑"的诚信佳话传世。',
  '周':'源自姬姓，周王朝王族之后以国为姓。汝南周氏为汉晋望族，宋代理学家周敦颐的《爱莲说》流芳百世。',
  '徐':'出自嬴姓，伯益之子若木受封建立徐国，国人以国为姓。东海徐氏自古人才济济。',
  '孙':'多出自姬姓与妫姓，春秋卫国孙乙、齐国孙书皆为得姓始祖。兵圣孙武、医圣孙思邈皆出孙氏。',
  '马':'出自嬴姓，战国赵将赵奢因功封"马服君"，子孙以马服为氏，后简为马。扶风马氏为东汉名门。',
  '朱':'出自曹姓，周封曹挟于邾国，后人去邑为朱。明朝国姓，沛国朱氏与紫阳朱熹一脉俱负盛名。',
  '胡':'出自妫姓，陈国开国之君胡公满的谥号为后人所承。安定胡氏为汉代望族，绵延千年。',
  '郭':'出自姬姓，周王封虢叔于虢国，"虢"音转为"郭"。汾阳郭氏因唐代名将郭子仪而天下知名。',
  '何':'出自姬姓，韩国灭亡后部分族人迁居江淮，当地"韩""何"音近，遂以何为姓。庐江何氏为东汉望族。',
  '林':'出自子姓，比干之子坚避难于长林山，周武王赐姓林。福建莆田林氏有"九牧林家"之美誉。',
  '罗':'出自妘姓，上古罗国（今湖北宜城一带）后人以国为姓。豫章罗氏为江西大族，名贤代出。',
  '高':'多出自姜姓，齐国公子高之孙傒以祖名为氏。渤海高氏自汉至唐英杰辈出。',
  '郑':'出自姬姓，周宣王封弟友于郑国，亡国后国人以国为姓。荥阳郑氏为中古时期一流高门。',
  '梁':'出自嬴姓，秦仲少子康受封于梁山，建梁国，后人以国为姓。安定梁氏为汉代外戚名门。',
  '谢':'出自任姓与姜姓，申伯受封于谢邑而得姓。陈郡谢氏在东晋与王氏并称"王谢"，风流冠绝江左。',
  '宋':'出自子姓，周封商纣王庶兄微子启于宋国，后人以国为姓，商丘为其发祥地。',
  '唐':'出自祁姓，尧帝号陶唐氏，其后人受封唐国，以国为姓。晋阳唐氏与鲁国唐氏皆有名望。',
  '许':'出自姜姓，炎帝后裔文叔受封于许国（今河南许昌），子孙以国为姓。高阳许氏为汉魏望族。',
  '韩':'出自姬姓，晋国韩武子之后三家分晋建韩国，亡国后以国为姓。南阳韩氏因唐代文宗韩愈而显。',
  '冯':'出自姬姓，毕公高后裔受封于冯城，以邑为氏。上党冯氏、杜陵冯氏皆为汉代大族。',
  '邓':'出自曼姓，商王武丁封叔父于邓国，后人以国为姓。南阳新野邓氏因东汉元勋邓禹而兴盛。',
  '曹':'出自姬姓，周武王封弟振铎于曹国，以国为姓。谯郡曹氏因魏武帝曹操而名垂青史。',
  '彭':'出自篯姓，传说中长寿的彭祖受封于大彭，后人以国为姓。陇西彭氏与宜春彭氏皆为望族。',
  '曾':'出自姒姓，夏少康封次子曲烈于鄫国，亡国后太子巫去邑为曾。宗圣曾子使曾氏以孝传家。',
  '肖':'多与"萧"同源。萧氏出自子姓，宋国大夫大心平乱有功受封萧邑。兰陵萧氏曾建齐梁两朝。',
  '萧':'出自子姓，宋国大夫大心受封于萧邑，以邑为氏。兰陵萧氏南朝建齐、梁两朝，文采武功并盛。',
  '田':'出自妫姓，陈国公子完奔齐改姓田，后代"田氏代齐"执掌齐国。雁门田氏为汉代边塞大族。',
  '董':'出自己姓，上古董父善于驯龙，舜帝赐姓董。陇西董氏与济阴董氏皆为汉代望族。',
  '潘':'出自姬姓，毕公高之子季孙食邑于潘，以邑为氏。荥阳潘氏因晋代才子潘岳而知名。',
  '袁':'出自妫姓，陈国大夫辕涛涂之后去车为袁。汝南袁氏东汉"四世五公"，门生故吏遍天下。',
  '蔡':'出自姬姓，周武王封弟叔度于蔡国，后人以国为姓。济阳蔡氏因东汉大儒蔡邕父女而流芳。',
  '蒋':'出自姬姓，周公第三子伯龄受封于蒋国，子孙以国为姓。乐安蒋氏为江南大族。',
  '余':'相传出自姬姓，春秋由余入秦为相，助秦穆公称霸西戎，后人以名为氏。下邳余氏为其郡望。',
  '于':'出自姬姓，周武王次子邘叔受封于邘国，后人去邑为于。河南于氏自古名将贤臣不绝。',
  '杜':'出自祁姓，尧帝后裔刘累之后受封于杜城，以邑为氏。京兆杜氏汉唐间将相满门，诗圣杜甫亦出此族。',
  '叶':'出自芈姓，楚国名臣沈诸梁受封叶邑，史称"叶公"，后人以邑为姓。南阳叶氏为其正宗。',
  '程':'出自风姓，重黎之后受封于程国，以国为姓。安定程氏与河南程氏（二程理学）皆名重一时。',
  '苏':'出自己姓，昆吾之子受封于苏国，以国为姓。眉山苏氏一门三杰，唐宋八大家独占其三。',
  '魏':'出自姬姓，毕万事晋受封魏地，三家分晋后建魏国，以国为姓。钜鹿魏氏因名相魏徵而显。',
  '吕':'出自姜姓，炎帝后裔伯夷受封吕国。姜子牙即出吕氏，河东吕氏宋代名相辈出。',
  '丁':'多出自姜姓，齐太公之子伋谥号"丁公"，子孙以谥为氏。济阳丁氏为其著名郡望。',
  '任':'出自风姓，为太昊伏羲氏之后，是最古老的姓氏之一。乐安任氏与东安任氏皆为望族。',
  '沈':'出自姬姓，周文王之子季载受封于沈国，后人以国为姓。吴兴沈氏为江南文献世家。',
  '姚':'出自妫姓，舜帝生于姚墟，以地为姓，是上古八大姓之一。吴兴姚氏为其望族。',
  '卢':'出自姜姓，齐国高傒食邑于卢，子孙以邑为氏。范阳卢氏为中古五姓七望之一，世称儒宗。',
  '姜':'上古八大姓之一，炎帝生于姜水，以水为姓。姜子牙封齐后支系繁衍，天水姜氏为其望。',
  '崔':'出自姜姓，齐国公子季子让国后食邑于崔，以邑为氏。清河、博陵崔氏并列中古一等高门。',
  '钟':'出自子姓，宋国公族伯宗之后食邑钟离，简为钟氏。颍川钟氏因书法之祖钟繇而名世。',
  '谭':'出自姒姓，周封禹后于谭国（今山东章丘），亡国后以国为姓。弘农谭氏为其郡望。',
  '陆':'出自妫姓，齐宣王少子通受封于陆乡，以乡为氏。吴郡陆氏自三国陆逊起为江东冠族。',
  '汪':'出自漆姓与姬姓，鲁国公族汪侯之后以名为氏。新安汪氏为徽州第一大姓。',
  '范':'出自祁姓，杜伯之孙士会食邑于范，以邑为氏。高平范氏因名臣范仲淹"先忧后乐"而垂范千古。',
  '金':'来源多元，或出自少昊金天氏，或为汉代金日磾之后。彭城金氏与京兆金氏皆有名望。',
  '石':'出自姬姓，卫国贤大夫石碏大义灭亲，后人以其字为氏。武威石氏为西北大族。',
  '廖':'出自己姓，上古廖叔安受封于飂国，后人改写为廖。汝南廖氏为其正宗郡望。',
  '贾':'出自姬姓，唐叔虞少子公明受封于贾国，以国为姓。武威贾氏与洛阳贾谊一脉俱有文名。',
  '夏':'出自姒姓，大禹建立夏朝，王族后裔以朝代为姓。会稽夏氏为其望族。',
  '韦':'出自彭姓，豕韦国后人以国为姓。京兆韦氏唐代与杜氏并称"城南韦杜，去天尺五"。',
  '傅':'出自殷商名相傅说，他筑墙为生而被武丁拜相，后人以其居地傅岩为氏。北地傅氏为汉晋望族。',
  '方':'出自姜姓，炎帝后裔方雷氏之后。河南方氏与桐城方氏以文章名世。',
  '白':'出自芈姓，楚国太子建之子胜受封白邑，称白公，后人以邑为氏。太原白氏因诗人白居易而显。',
  '邹':'出自曹姓，邾国分支邾娄小邾子受封于邹，以国为姓。范阳邹氏为其郡望。',
  '孟':'出自姬姓，鲁国公族庆父之后改称孟孙氏，简为孟。亚圣孟子使孟氏以儒学传家。',
  '熊':'出自芈姓，楚国王族以先祖鬻熊之名为氏。江陵熊氏与豫章熊氏皆为南方大族。',
  '秦':'出自嬴姓与姬姓，或为秦国王族之后，或为鲁国大夫秦遄之后。天水秦氏为其望。',
  '邱':'与"丘"同源，出自姜姓，姜太公封齐建都营丘，子孙以地为氏，清代避讳加邑为邱。',
  '江':'出自嬴姓，伯益之后受封江国（今河南正阳一带），亡国后以国为姓。济阳江氏为南朝文学世家。',
  '尹':'出自少昊之子殷，任工正受封尹城，以邑为氏。天水尹氏与河间尹氏皆为望族。',
  '薛':'出自任姓，夏代奚仲任车正受封薛国，后人以国为姓。河东薛氏为关西六大姓之一。',
  '雷':'出自方雷氏，黄帝臣子雷公精于医道，后人以雷为姓。冯翊雷氏为其郡望。',
  '侯':'多出自姬姓，晋国公族受封侯邑，或以爵位为氏。上谷侯氏为汉代名门。',
  '龙':'来源古老，或出自舜臣纳言龙，或出自御龙氏。武陵龙氏与武阳龙氏皆有声望。',
  '史':'出自周代太史官，史佚之后以官为氏。京兆史氏与宣城史氏皆为望族。',
  '陶':'出自唐尧，尧帝曾以制陶为业，号陶唐氏，后人以陶为姓。浔阳陶氏因隐逸之宗陶渊明而高洁传世。',
  '黎':'出自九黎之后，或商代黎国子孙以国为姓。京兆黎氏为其郡望，宋有名士黎錞。',
  '贺':'出自姜姓，齐国庆封之后避汉安帝讳改"庆"为"贺"。会稽贺氏为江南望族，贺知章即出此门。',
  '顾':'出自己姓与越国王族，汉代越王勾践后裔摇封其子于顾余，以邑为氏。吴郡顾氏为江东四姓之首。',
  '毛':'出自姬姓，周文王之子叔郑受封毛国，以国为姓。西河毛氏注《诗经》传世，世称"毛诗"。',
  '郝':'出自子姓，商王帝乙封弟于郝乡，后人以乡为氏。太原郝氏为其正宗。',
  '龚':'出自共工氏之后，为避祸加龙为龚。武陵龚氏为其望族，宋有清官龚茂良。',
  '邵':'出自姬姓，周初三公之一召公奭之后，加邑为邵。博陵邵氏因宋代易学大家邵雍而显。',
  '万':'出自姬姓，晋国大夫毕万之后以名为氏。扶风万氏为其郡望。',
  '钱':'出自篯姓，彭祖后裔篯孚任周代钱府上士，以官为氏。吴越钱氏开创"上有天堂"的钱塘盛景，家训传世。',
  '严':'出自芈姓，楚庄王之后以谥为庄氏，东汉避明帝讳改严。天水严氏与富春严子陵俱有高名。',
  '武':'出自子姓，商王武丁与周代武氏士人皆为得姓之源。太原武氏因唐代女皇武则天而载入史册。',
  '戴':'出自子姓，宋戴公之后以谥为氏。谯郡戴氏与广陵戴氏皆以经学闻名。',
  '莫':'出自高阳氏，颛顼造鄚阳城，子孙去邑为莫。江陵莫氏为其望族。',
  '孔':'出自子姓，宋国公族孔父嘉之后以字为氏。至圣孔子使曲阜孔氏成为延续两千多年的天下第一家。',
  '向':'出自子姓，宋桓公之子肸字向父，后人以字为氏。河南向氏为其郡望。',
  '汤':'出自子姓，商朝开国之君成汤的后裔以先祖名号为姓。中山汤氏与范阳汤氏皆为望族。',
  '常':'出自姬姓，卫康叔支孙食邑于常，以邑为氏。平原常氏为汉代名门。',
  '温':'出自姬姓，唐叔虞之后受封于温邑，以邑为氏。太原温氏唐代一门三相。',
  '康':'出自姬姓，卫国开国之君康叔的后裔以其谥号为氏。京兆康氏为其望。',
  '施':'出自姬姓，鲁惠公之子尾生字施父，后人以字为氏。吴兴施氏为江南旧族。',
  '文':'出自姬姓，周文王支庶以谥号为氏。雁门文氏因宋代忠烈文天祥而气贯长虹。',
  '牛':'出自子姓，宋微子之后司寇牛父，子孙以字为氏。陇西牛氏为其郡望。',
  '樊':'出自姬姓，周宣王名臣仲山甫受封樊邑，以邑为氏。上党樊氏为汉代望族。',
  '葛':'出自嬴姓，夏代葛国之后以国为姓。顿丘葛氏与琅琊诸葛同源。',
  '欧阳':'出自姒姓，越王勾践之后蹄受封乌程欧余山之阳，称欧阳亭侯，遂以为氏。宋代文宗欧阳修使此姓文名满天下。',
  '司马':'出自官职，周代掌军政的"司马"之后以官为氏。河内司马氏建立晋朝，史家司马迁、司马光皆为此姓之光。',
  '上官':'出自芈姓，楚庄王少子兰任上官大夫，后人以官为氏。天水上官氏为其郡望。',
  '诸葛':'出自葛姓，琅琊诸县葛氏迁居阳都，为别于当地葛姓而称诸葛。武侯诸葛亮使此姓智慧之名千古流传。',
  '东方':'出自伏羲氏，按八卦方位震位居东方，后人以方位为姓。汉代东方朔机智诙谐，为此姓增色。',
  '皇甫':'出自子姓，宋戴公之子充石字皇父，后人改父为甫。安定皇甫氏汉唐间名将名医辈出。',
  '尉迟':'出自鲜卑尉迟部，北魏孝文帝改革后融入中原。唐初名将尉迟敬德为此姓代表人物。',
  '令狐':'出自姬姓，晋国魏颗受封令狐之地，后人以邑为氏。太原令狐氏唐代为相门。',
  '南宫':'出自姬姓，周文王"八士"之一南宫适之后，以居地为氏。鲁郡为其郡望。',
  '西门':'出自姬姓，郑国公族居于城西门，以居地为氏。战国西门豹治邺的故事使此姓流传。',
};
const DOUBLE_SUR = ['欧阳','司马','上官','诸葛','东方','皇甫','尉迟','令狐','南宫','西门'];

/* ===================== 工具 ===================== */
const $ = id => document.getElementById(id);
function hashStr(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
  return h >>> 0;
}
function mulberry(seed) {
  return () => {
    seed |= 0; seed = seed + 0x6D2B79F5 | 0;
    let t = Math.imul(seed ^ seed >>> 15, 1 | seed);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}
const pick = (rng, arr) => arr[Math.floor(rng() * arr.length)];

/* ===================== 八字推算（近似节气，仅供娱乐） ===================== */
const TERM_STARTS = [[2,4],[3,6],[4,5],[5,6],[6,6],[7,7],[8,8],[9,8],[10,8],[11,7],[12,7],[1,6]]; // 寅..丑
function bazi(y, m, d, hourIdx) {
  // 年柱（立春前算上一年）
  let yy = y;
  if (m < 2 || (m === 2 && d < 4)) yy--;
  const yGan = ((yy - 4) % 10 + 10) % 10;
  const yZhi = ((yy - 4) % 12 + 12) % 12;
  // 月柱（按近似节气定月支，五虎遁定月干）
  let mIdx = 11; // 默认丑月
  for (let i = 0; i < 12; i++) {
    const [sm, sd] = TERM_STARTS[i];
    const next = TERM_STARTS[(i + 1) % 12];
    const after = (m > sm || (m === sm && d >= sd));
    const before = (m < next[0] || (m === next[0] && d < next[1]));
    if (i < 11 ? (after && before) : (after || before)) { mIdx = i; break; }
  }
  const mZhi = (mIdx + 2) % 12;
  const mGan = ((yGan % 5) * 2 + 2 + mIdx) % 10;
  // 日柱（以 1949-10-01 甲子日为锚点）
  const days = Math.floor((Date.UTC(y, m - 1, d) - Date.UTC(1949, 9, 1)) / 86400000);
  const dIdx = ((days % 60) + 60) % 60;
  const dGan = dIdx % 10, dZhi = dIdx % 12;
  // 时柱（五鼠遁）
  let pillars = [
    { lab: '年柱', gan: yGan, zhi: yZhi },
    { lab: '月柱', gan: mGan, zhi: mZhi },
    { lab: '日柱', gan: dGan, zhi: dZhi },
  ];
  if (hourIdx >= 0) {
    const hGan = ((dGan % 5) * 2 + hourIdx) % 10;
    pillars.push({ lab: '时柱', gan: hGan, zhi: hourIdx });
  }
  return pillars;
}

/* ===================== 文案生成 ===================== */
const ELEM_PERSONA = {
  '金':'日主属金，性情刚毅果决，重义守信，认定的事便一往无前。金性贵在淬炼，历经磨砺更显锋芒。',
  '木':'日主属木，生机勃发，心怀仁厚，如春树向阳而长，既有韧性又有担当，是众人眼中可靠的依靠。',
  '水':'日主属水，聪慧灵动，善于变通，遇山绕山、遇石穿石，以柔克刚是你与生俱来的智慧。',
  '火':'日主属火，热情明亮，行动力极强，走到哪里都自带光芒，能点燃身边人的干劲与希望。',
  '土':'日主属土，敦厚沉稳，包容守成，如大地承载万物，越是关键时刻越能显出你的可靠与分量。',
};
const NAME_ELEM_TXT = {
  '金':'名字中暗藏金石之音，行事干脆，掷地有声。',
  '木':'名字中带着草木清气，温润育人，自有生发之象。',
  '水':'名字里流转着水的灵气，思维活泛，处世圆融。',
  '火':'名字里跳动着火的光华，气场明亮，感染力强。',
  '土':'名字中蕴含厚土之德，根基扎实，让人安心。',
};
const LUCK_TXT = [
  '近期整体气运平稳向上，过去种下的因正在悄悄结果，保持耐心便能看到回报。',
  '运势如初春之水，表面平静，底下暗流涌动，新的机会正在靠近，留意身边的变化。',
  '吉星照拂，贵人缘旺，多走动、多交流，关键的助力往往来自一次不经意的交谈。',
  '气运正处在蓄力阶段，宜静不宜躁，把基本功打牢，下一波上升期来临时方能稳稳接住。',
  '运势带有突破之象，过去卡住的事情近期有望松动，主动推一把，胜过被动等待。',
  '整体运程外柔内刚，看似波澜不惊，实则步步为营，按自己的节奏走，不必羡慕他人。',
];
const WEALTH_TXT = [
  '正财稳健，靠本事吃饭的收入会稳步增长；偏财平平，投机之事浅尝辄止为宜。',
  '财帛宫有流动之象，钱财进出都较活跃，记好账、管住手，结余自然慢慢厚实。',
  '有"小财不断"之兆，零散的进项汇聚起来颇为可观，别小看每一笔小收入。',
  '财运与人脉紧密相连，与人合作、资源互换，比单打独斗更容易见到真金白银。',
  '近期适合开源更适合节流，砍掉不必要的开支，便等于多赚了一份。',
  '财气藏于专业之中，技能越精，身价越高，投资自己是眼下回报率最高的选择。',
];
const LOVE_TXT = [
  '感情运温润如玉，有伴者宜多陪伴少争辩，单身者的缘分多在熟人圈子里。',
  '桃花隐隐欲动，最近不妨多参加聚会走动，一段投缘的关系可能就在不远处。',
  '感情上讲究"慢火炖汤"，急不得，真诚和时间会替你筛选出对的人。',
  '有旧缘回温之象，无论友情还是爱情，主动问候一句，可能换来意想不到的暖意。',
  '感情运中带着考验，小摩擦其实是了解彼此的机会，话说开了感情反而更深。',
  '心有所属者宜表达，藏在心里的话不说出口，对方永远只能猜，勇敢一点。',
];
const CAREER_TXT = [
  '事业宫气象向好，手头的事踏实做完，能见度和口碑都会随之提升。',
  '有"贵人提携"之象，前辈或上级的一句话可能为你打开新的门，保持谦逊多请教。',
  '近期适合学习进修，新技能将成为下一阶段事业的敲门砖，越早储备越从容。',
  '事业上有变动之象，变动并非坏事，新的位置或方向可能更适合施展拳脚。',
  '宜守正出奇：日常事务按部就班，同时悄悄打磨一件让人眼前一亮的作品。',
  '团队协作是近期关键词，懂得借力与分功的人，走得比独行侠更远。',
];
const HEALTH_TXT = [
  '体气尚足，唯须留意作息，少熬夜，元气养住了，做什么都有劲。',
  '注意劳逸结合，久坐伤神，每天起身走一走、望望远处，胜过补药。',
  '脾胃宜养，规律三餐、少食生冷，身体的底子是一餐一饭垒起来的。',
  '近期宜动起来，快走、慢跑、拉伸皆可，微微出汗最能疏通气血。',
  '心宽则体健，少思虑、多舒展，心情顺了，小毛病自然绕道走。',
];
const CLOSER = [
  '总而言之，行好事、存善念，运随心转，路在脚下。',
  '记住：命是底牌，运是出牌的方式，牌好不如打得好。',
  '所谓好运，多半留给有准备又肯行动的人。',
  '顺境不骄，逆境不馁，便是最好的开运之法。',
];
const ELEM_COLOR = { '金':'白色与金色', '木':'青色与绿色', '水':'蓝色与黑色', '火':'红色与紫色', '土':'黄色与棕色' };
const ELEM_DIR = { '金':'西方', '木':'东方', '水':'北方', '火':'南方', '土':'中央与西南' };

function stars(rng) {
  const n = 3 + Math.floor(rng() * 5) / 2;           // 3 ~ 5
  const full = Math.floor(n), half = n % 1 !== 0;
  return '★'.repeat(full) + (half ? '✬' : '') + '☆'.repeat(5 - full - (half ? 1 : 0));
}

/* ===================== 背景画面 ===================== */
const bg = $('bg'), bctx = bg.getContext('2d');
let bw = 0, bh = 0;
function resize() { bw = bg.width = innerWidth; bh = bg.height = innerHeight; }
addEventListener('resize', resize); resize();
const motes = Array.from({ length: 70 }, () => ({
  x: Math.random() * 2000, y: Math.random() * 2000,
  r: 0.6 + Math.random() * 2.2, v: 6 + Math.random() * 18, p: Math.random() * 6.28,
}));
const TRIGRAMS = [[1,1,1],[0,1,1],[1,0,1],[0,0,1],[1,1,0],[0,1,0],[1,0,0],[0,0,0]];
function drawBg(t) {
  bctx.clearRect(0, 0, bw, bh);
  const g = bctx.createRadialGradient(bw/2, bh*0.35, 60, bw/2, bh*0.35, Math.max(bw, bh)*0.8);
  g.addColorStop(0, '#262019'); g.addColorStop(1, '#120e0b');
  bctx.fillStyle = g; bctx.fillRect(0, 0, bw, bh);
  // 水墨云霭
  bctx.globalAlpha = 0.05;
  for (let i = 0; i < 4; i++) {
    const cx = bw/2 + Math.sin(t*0.00006 + i*2.1) * bw*0.4;
    const cy = bh*0.25 + Math.cos(t*0.00005 + i*1.7) * bh*0.3;
    const gr = bctx.createRadialGradient(cx, cy, 10, cx, cy, 280);
    gr.addColorStop(0, '#d8b455'); gr.addColorStop(1, 'rgba(216,180,85,0)');
    bctx.fillStyle = gr;
    bctx.beginPath(); bctx.arc(cx, cy, 280, 0, 6.29); bctx.fill();
  }
  bctx.globalAlpha = 1;
  // 旋转八卦环
  bctx.save();
  bctx.translate(bw/2, bh*0.36);
  bctx.rotate(t * 0.00004);
  bctx.globalAlpha = 0.10;
  bctx.strokeStyle = '#d8b455'; bctx.lineWidth = 2;
  const R0 = Math.min(bw, bh) * 0.34;
  bctx.beginPath(); bctx.arc(0, 0, R0 + 36, 0, 6.29); bctx.stroke();
  bctx.beginPath(); bctx.arc(0, 0, R0 - 28, 0, 6.29); bctx.stroke();
  for (let i = 0; i < 8; i++) {
    bctx.save();
    bctx.rotate(i * Math.PI / 4);
    bctx.translate(0, -R0);
    for (let l = 0; l < 3; l++) {
      const y = (l - 1) * 12;
      if (TRIGRAMS[i][l]) { bctx.beginPath(); bctx.moveTo(-16, y); bctx.lineTo(16, y); bctx.stroke(); }
      else {
        bctx.beginPath(); bctx.moveTo(-16, y); bctx.lineTo(-3, y); bctx.stroke();
        bctx.beginPath(); bctx.moveTo(3, y); bctx.lineTo(16, y); bctx.stroke();
      }
    }
    bctx.restore();
  }
  bctx.restore();
  // 金色浮尘
  for (const m of motes) {
    const x = (m.x + Math.sin(t*0.0004 + m.p) * 30) % (bw + 60) - 30;
    const y = (m.y - t * 0.00002 * m.v * 60) % (bh + 60);
    const yy = y < -30 ? y + bh + 60 : y;
    bctx.globalAlpha = 0.25 + 0.25 * Math.sin(t*0.002 + m.p);
    bctx.fillStyle = '#e8cd8a';
    bctx.beginPath(); bctx.arc(x, yy, m.r, 0, 6.29); bctx.fill();
  }
  bctx.globalAlpha = 1;
}
(function bgLoop(t) { drawBg(t || 0); requestAnimationFrame(bgLoop); })();

/* ===================== 古风背景音乐（生成式，原创） ===================== */
let AC = null, musicOn = false, musicTimer = null;
const PENTA = [0, 2, 4, 7, 9];                       // 宫商角徵羽
function note2f(n) { return 220 * Math.pow(2, n / 12); }
function pluck(freq, when, vol, dur) {
  const o1 = AC.createOscillator(), o2 = AC.createOscillator(), g = AC.createGain();
  o1.type = 'triangle'; o2.type = 'sine';
  o1.frequency.value = freq; o2.frequency.value = freq * 2.005;
  g.gain.setValueAtTime(vol, when);
  g.gain.exponentialRampToValueAtTime(0.0008, when + dur);
  o1.connect(g); o2.connect(g);
  g.connect(AC.destination); g.connect(echo);
  o1.start(when); o2.start(when);
  o1.stop(when + dur + 0.05); o2.stop(when + dur + 0.05);
}
let echo = null;
function startMusic() {
  if (!AC) {
    AC = new (window.AudioContext || window.webkitAudioContext)();
    echo = AC.createDelay(); echo.delayTime.value = 0.42;
    const fb = AC.createGain(); fb.gain.value = 0.34;
    const wet = AC.createGain(); wet.gain.value = 0.5;
    echo.connect(fb); fb.connect(echo); echo.connect(wet); wet.connect(AC.destination);
    const drone = AC.createOscillator(), dg = AC.createGain(), df = AC.createBiquadFilter();
    drone.type = 'sawtooth'; drone.frequency.value = 55;
    df.type = 'lowpass'; df.frequency.value = 120;
    dg.gain.value = 0.025;
    drone.connect(df); df.connect(dg); dg.connect(AC.destination);
    drone.start();
  }
  if (AC.state === 'suspended') AC.resume();
  if (musicTimer) return;
  let next = AC.currentTime + 0.2, phraseStep = 0;
  musicTimer = setInterval(() => {
    while (next < AC.currentTime + 0.6) {
      const oct = Math.random() < 0.3 ? 12 : 0;
      const deg = PENTA[Math.floor(Math.random() * 5)];
      pluck(note2f(deg + oct + 12), next, 0.10, 1.8);
      if (Math.random() < 0.3) pluck(note2f(deg - 12 + 7), next + 0.08, 0.05, 2.2);
      phraseStep++;
      const gap = (phraseStep % 7 === 0) ? 1.6 : (0.35 + Math.random() * 0.7);
      next += gap;
    }
  }, 200);
}
function stopMusic() { if (musicTimer) { clearInterval(musicTimer); musicTimer = null; } if (AC) AC.suspend(); }
$('musicBtn').addEventListener('click', () => {
  musicOn = !musicOn;
  $('musicBtn').textContent = musicOn ? '🔇 止乐' : '🎵 奏乐';
  if (musicOn) startMusic(); else stopMusic();
});

/* ===================== 主流程 ===================== */
const LOAD_LINES = ['研墨铺纸…', '推演天干地支…', '细察五行旺衰…', '翻阅百家姓谱…', '提笔批注命书…'];
$('goBtn').addEventListener('click', () => {
  const name = $('inName').value.trim();
  if (!/^[一-龥·]{2,6}$/.test(name)) {
    $('inName').style.borderColor = '#ff6a5a';
    $('inName').placeholder = '请输入 2~6 个汉字的姓名';
    $('inName').value = '';
    return;
  }
  $('formCard').style.display = 'none';
  $('result').style.display = 'none';
  $('result').innerHTML = '';
  $('loading').style.display = 'block';
  let li = 0;
  $('loadTxt').textContent = LOAD_LINES[0];
  const lt = setInterval(() => { li = (li + 1) % LOAD_LINES.length; $('loadTxt').textContent = LOAD_LINES[li]; }, 500);
  setTimeout(() => { clearInterval(lt); $('loading').style.display = 'none'; render(name); }, 2600);
});

function render(name) {
  const dateStr = $('inDate').value;
  const hourIdx = parseInt($('inHour').value, 10);
  const rng = mulberry(hashStr(name + '|' + dateStr + '|' + hourIdx));

  // 姓氏
  let sur = name.slice(0, 2);
  if (!DOUBLE_SUR.includes(sur)) sur = name[0];
  const given = name.slice(sur.length) || name;
  const surTxt = SURNAMES[sur] ||
    `“${sur}”氏源远流长，是中华姓氏大家庭中独具风骨的一支。千百年来族人遍布各地，以勤勉与才识立身，家风代代相传。`;

  // 名字五行
  const nameElem = WX[hashStr(given) % 5];

  // 八字
  let baziHtml = '', persona = '', domElem = nameElem, weakElem = WX[(WX.indexOf(nameElem) + 2) % 5];
  if (dateStr) {
    const [y, m, d] = dateStr.split('-').map(Number);
    const ps = bazi(y, m, d, hourIdx);
    const count = { '金':0, '木':0, '水':0, '火':0, '土':0 };
    for (const p of ps) { count[GAN_WX[p.gan]]++; count[ZHI_WX[p.zhi]]++; }
    const total = ps.length * 2;
    domElem = GAN_WX[ps[2].gan];                                   // 日主
    weakElem = WX.reduce((a, b) => count[a] <= count[b] ? a : b);
    persona = ELEM_PERSONA[domElem];
    const pillarHtml = ps.map(p => `
      <div class="pillar">
        <div class="lab">${p.lab}</div>
        <div class="gz"><span class="e${GAN_WX[p.gan]}">${GAN[p.gan]}</span><span class="e${ZHI_WX[p.zhi]}">${ZHI[p.zhi]}</span></div>
        <div class="wx"><span class="e${GAN_WX[p.gan]}">${GAN_WX[p.gan]}</span> <span class="e${ZHI_WX[p.zhi]}">${ZHI_WX[p.zhi]}</span></div>
      </div>`).join('');
    const wxHtml = WX.map(e => `
      <div class="wxrow"><span class="n e${e}">${e}</span>
        <div class="wxbar"><i class="b${e}" style="width:${Math.round(count[e] / total * 100)}%"></i></div>
        <span class="n">${count[e]}</span></div>`).join('');
    baziHtml = `
      <div class="card"><h2>🀄 生辰八字</h2>
        <div class="pillars">${pillarHtml}</div>
        ${hourIdx < 0 ? '<p class="note">未填时辰，故只排年、月、日三柱。</p>' : ''}
        <div class="wuxing">${wxHtml}</div>
        <p style="margin-top:14px">${persona} 命局中「${weakElem}」稍弱，平日可亲近${ELEM_DIR[weakElem]}方位、多用${ELEM_COLOR[weakElem]}，以补其气。</p>
        <p class="note">注：节气以常见日期近似推算，与万年历或有一两日出入。</p>
      </div>`;
  } else {
    persona = ELEM_PERSONA[nameElem];
    baziHtml = `
      <div class="card"><h2>🀄 生辰八字</h2>
        <p>${NAME_ELEM_TXT[nameElem]} ${persona}</p>
        <p class="note">提示：返回填写出生日期与时辰，可解锁完整四柱排盘与五行分布。</p>
      </div>`;
  }

  const section = (icon, title, sts, txt) => `
    <div class="card"><h2>${icon} ${title}</h2>
      ${sts ? `<div class="stars">${sts}</div>` : ''}
      <p>${txt}</p>
    </div>`;

  $('result').innerHTML = `
    <div class="bigname">${name}</div>
    ${section('🏯', '姓氏渊源', '', `<b class="e土">「${sur}」</b>—— ${surTxt}`)}
    ${baziHtml}
    ${section('🌅', '综合运势', stars(rng), pick(rng, LUCK_TXT) + ' ' + pick(rng, CLOSER))}
    ${section('💰', '财运', stars(rng), pick(rng, WEALTH_TXT))}
    ${section('💗', '爱情', stars(rng), pick(rng, LOVE_TXT))}
    ${section('🏔️', '事业', stars(rng), pick(rng, CAREER_TXT))}
    ${section('🍵', '健康', stars(rng), pick(rng, HEALTH_TXT))}
    <div class="card"><h2>🧧 幸运指南</h2>
      <div class="lucky">
        <span class="tag">幸运色：${ELEM_COLOR[weakElem]}</span>
        <span class="tag">幸运数字：${1 + Math.floor(rng() * 9)} 与 ${1 + Math.floor(rng() * 9)}</span>
        <span class="tag">吉位：${ELEM_DIR[weakElem]}</span>
        <span class="tag">宜：${pick(rng, ['早起','读书','访友','远行','整理','运动','静坐','尝新'])}</span>
        <span class="tag">忌：${pick(rng, ['熬夜','拖延','冲动消费','争执','久坐','多虑'])}</span>
      </div>
    </div>
    <button class="btn" id="againBtn">再 测 一 位</button>`;
  $('result').style.display = 'block';

  const cards = $('result').querySelectorAll('.card, .bigname');
  cards.forEach((c, i) => setTimeout(() => c.classList.add('show'), 120 + i * 220));
  $('result').querySelectorAll('.bigname').forEach(b => b.classList.add('show'));
  $('againBtn').addEventListener('click', () => {
    $('result').style.display = 'none';
    $('formCard').style.display = 'block';
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });
}
})();
