"use strict";
/* Ooglex Indicator Ratings V2 — observational snapshot only; never synthesize a market quote. */
(()=>{
const $=id=>document.getElementById(id);
const isFiniteNumber=n=>typeof n==="number"&&Number.isFinite(n);
const validDay=x=>typeof x==="string"&&/^\d{4}-\d{2}-\d{2}$/.test(x)&&!Number.isNaN(Date.parse(x+"T00:00:00Z"))&&new Date(x+"T00:00:00Z").toISOString().slice(0,10)===x;
const dayAge=x=>validDay(x)?Math.floor((Date.now()-Date.parse(x+"T00:00:00Z"))/86400000):Infinity;
const monthAge=x=>{if(typeof x!=="string"||!/^\d{4}-(0[1-9]|1[0-2])$/.test(x))return Infinity;const [y,m]=x.split("-").map(Number),now=new Date();return (now.getUTCFullYear()-y)*12+now.getUTCMonth()+1-m};
const definitions=[
{name:"美国10年期实际收益率",read:d=>({value:d.rates?.real10y,period:d.observation_date,unit:"%",fresh:7,kind:"day",origin:"美国财政部 TIPS",link:"https://fred.stlouisfed.org/series/DFII10"})},
{name:"美国10年期国债收益率",read:d=>({value:d.rates?.us10y,period:d.observation_date,unit:"%",fresh:7,kind:"day",origin:"美国财政部",link:"https://home.treasury.gov/resource-center/data-chart-center/interest-rates"})},
{name:"美国2年期国债收益率",read:d=>({value:d.rates?.us2y,period:d.observation_date,unit:"%",fresh:7,kind:"day",origin:"美国财政部",link:"https://home.treasury.gov/resource-center/data-chart-center/interest-rates"})},
{name:"10Y－2Y期限利差",read:d=>({value:d.rates?.spread10y2y,period:d.observation_date,unit:"百分点",fresh:7,kind:"day",origin:"财政部同日收益率衍生",link:"https://home.treasury.gov/resource-center/data-chart-center/interest-rates"})},
{name:"10年盈亏平衡通胀率",read:d=>({value:d.rates?.breakeven10y,period:d.observation_date,unit:"%",fresh:7,kind:"day",origin:"财政部同日名义与TIPS收益率差",link:"https://home.treasury.gov/resource-center/data-chart-center/interest-rates"})},
{name:"美国非农就业与失业率",read:d=>({value:d.bls?.series?.unemployment?.value,period:d.bls?.series?.unemployment?.period,unit:"%失业率",fresh:2,kind:"month",origin:"BLS（非农就业请至宏观指标中心）",link:"https://www.bls.gov/ces/"})},
{name:"美国核心PCE同比",read:d=>({value:d.bea?.core_pce?.yoy_percent,period:d.bea?.core_pce?.observation_period,unit:"%同比",fresh:3,kind:"month",origin:"BEA 经FRED镜像 · 修订观测",link:"https://www.bea.gov/data/personal-consumption-expenditures-price-index"})},
{name:"美联储资产负债表总资产",read:d=>({value:d.fed_h41?.total_assets?.value_millions_usd,period:d.fed_h41?.total_assets?.observation_date,unit:"百万美元",fresh:14,kind:"day",origin:"美联储 H.4.1 经FRED镜像",link:"https://www.federalreserve.gov/releases/h41/"})},
{name:"准备金、TGA与ON RRP",read:d=>({value:d.liquidity?.reserves?.value,period:d.liquidity?.reserves?.observation_date,unit:"百万美元准备金",fresh:14,kind:"day",origin:"美联储 H.4.1 · 周平均；组件不能直接相加",link:"https://www.federalreserve.gov/releases/h41/"})},
{name:"美国CPI总体同比",read:d=>({value:null,period:d.bls?.series?.cpi?.period,unit:"%同比",fresh:2,kind:"month",origin:"BLS · 当前同比缺可比基期，暂不提供",link:"https://www.bls.gov/cpi/"})}
];
function badge(text,cls){const span=document.createElement("span");span.className="obs-pill "+cls;span.textContent=text;return span}
function cell(tr,text){const td=document.createElement("td");td.textContent=String(text);tr.append(td);return td}
function draw(d){const tb=$("obs-rows"),summary=$("obs-summary");if(!tb||!summary)return;tb.replaceChildren();let valid=0,stale=0,missing=0;
for(const item of definitions){const p=item.read(d),age=p.kind==="month"?monthAge(p.period):dayAge(p.period),fresh=age>=0&&age<=p.fresh,hasNumber=isFiniteNumber(p.value),status=hasNumber?(fresh?"可用观测":"过期观测"):"缺失";
if(status==="可用观测")valid++;else if(status==="过期观测")stale++;else missing++;
const tr=document.createElement("tr"),a=cell(tr,item.name);a.style.fontWeight="650";
cell(tr,hasNumber&&fresh?(p.unit==="百万美元"?p.value.toLocaleString("en-US",{maximumFractionDigits:0}):p.value.toLocaleString("en-US",{maximumFractionDigits:3}))+" "+p.unit:"—");
cell(tr,validDay(p.period)||/^\d{4}-\d{2}$/.test(p.period||"")?p.period:"—");
const td=document.createElement("td");td.append(badge(status,status==="可用观测"?"obs-verified":status==="过期观测"?"obs-stale":"obs-missing"));tr.append(td);
const src=document.createElement("td"),link=document.createElement("a");link.href=p.link;link.target="_blank";link.rel="noopener noreferrer";link.textContent=p.origin;src.append(link);tr.append(src);tb.append(tr)}
const gen=typeof d.generated_at==="string"&&!Number.isNaN(Date.parse(d.generated_at))?new Date(d.generated_at).toLocaleString("zh-CN",{timeZone:"UTC",hour12:false})+" UTC":"时间未核验";
summary.textContent="已核验的站内数据快照："+valid+" 项可用、"+stale+" 项过期、"+missing+" 项缺失（监测样本10项；评级目录总数40项）。生成于 "+gen+"。不同频率使用独立有效期；过期与缺失不展示行情数值。";}
async function start(){const target=$("obs-summary");if(!target)return;try{const response=await fetch("../data/asset-scores.json",{cache:"no-store"});if(!response.ok)throw Error("HTTP "+response.status);const d=await response.json();if(d?.schema_version!==1||typeof d.generated_at!=="string"||Number.isNaN(Date.parse(d.generated_at)))throw Error("数据结构或生成时间未通过验证");if(Date.parse(d.generated_at)>Date.now()+3600000)throw Error("快照生成时间异常");draw(d)}catch(e){target.textContent="站内数据未通过验证或暂时不可读取："+e.message+"。不以演示数字代替。";$("obs-rows")?.replaceChildren();}}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start,{once:true});else start();
})();