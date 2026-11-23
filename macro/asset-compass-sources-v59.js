"use strict";
// V59 independent research display. Never allow source-presence to unlock an asset score.
(() => {
  const target = document.getElementById("source-provenance-v59");
  if (!target) return;
  const names = {gold:"黄金",us_equities:"美股",us_long_bonds:"长期美债",
                 usd:"美元",bitcoin:"比特币",oil:"原油"};
  const expected = ["gold","us_equities","us_long_bonds","usd","bitcoin","oil"];
  function line(parent, tag, value, cls="") {
    const n=document.createElement(tag); if(cls)n.className=cls;
    n.textContent=String(value);parent.append(n);return n;
  }
  function warning(message) {
    target.replaceChildren();line(target,"p",message,"insights-warning");
  }
  async function read(path) {
    const r=await fetch(path,{cache:"no-store"});
    if(!r.ok)throw Error("not published: "+path);
    return r.json();
  }
  function fresh(date,days) {
    const time=Date.parse(date);
    return Number.isFinite(time)&&Date.now()>=time&&Date.now()-time<=days*86400000;
  }
  (async () => {
    let model;
    try {model=await read("../data/asset-compass-model-gaps-v59.json");}
    catch {warning("V59 官方来源采集尚未完成：继续沿用 V58 的 4/6 审计，不生成模拟资产数据。");return;}
    const verified=model?.source_verification;
    if(model?.schema_version!==1 ||
       model.report_type!=="asset_compass_v59_two_missing_asset_research_provenance" ||
       model.status!=="research_only_no_authorized_scores"||
       model.qualified_for_live_scoring!==false||
       model.official_0_to_100_scores_published!==0||
       model.audited_asset_total_return_count!==0||
       model.historical_first_release_certified_source_count!==0||
       model.oos_validated_assets!==0||
       !verified||
       !Array.isArray(model.asset_specific_observed_assets)||
       !Array.isArray(model.asset_specific_missing_assets)||
       model.asset_specific_observed_count+
         model.asset_specific_missing_count!==6||
       model.asset_specific_observed_assets.length!==
         model.asset_specific_observed_count||
       !expected.every(id => model.research_assets?.[id]?.official_score===null)||
       !expected.every(id => model.research_assets?.[id]?.point_in_time_provenance_verified===false)||
       !expected.every(id => model.research_assets?.[id]?.investable_total_return_verified===false)||
       !expected.every(id => model.research_assets?.[id]?.out_of_sample_backtest_verified===false)||
       !expected.every(id => model.asset_specific_observed_assets.includes(id) !==
                      model.asset_specific_missing_assets.includes(id))||
       verified.us_equities?.observed !== model.asset_specific_observed_assets.includes("us_equities")||
       verified.bitcoin?.observed !== model.asset_specific_observed_assets.includes("bitcoin")) {
      warning("V59 研究证据链与六资产评分禁令不一致，已拒绝展示。");
      return;
    }
    target.replaceChildren();
    line(target,"p",
      "已核验资产专属研究来源："+model.asset_specific_observed_count+
      "/6；未接入："+model.asset_specific_missing_count+
      "/6；可投资总回报认证：0/6；历史 PIT 与样本外认证：0/6；正式资产评分：0/6。","muted");
    const table=document.createElement("table"), thead=document.createElement("thead");
    const tr=document.createElement("tr");
    ["资产","来源及数据口径","状态"].forEach(h=>line(tr,"th",h));
    thead.append(tr);table.append(thead);
    const tbody=document.createElement("tbody");
    for(const id of expected){
      const r=document.createElement("tr");
      line(r,"td",names[id]);
      const source=model.research_assets[id].source_ids?.join("、")||"暂无可信专属观测";
      line(r,"td",source);
      line(r,"td",model.asset_specific_observed_assets.includes(id)?"仅限研究，未认证评分":"未完成");
      tbody.append(r);
    }
    table.append(tbody);
    const wrap=document.createElement("div");wrap.className="table-wrap";wrap.append(table);
    target.append(wrap);
    if(verified.us_equities?.observed){
      try{
        const eq=await read("../data/asset-compass-equities-z1-v59.json");
        if(eq.report_type!=="asset_compass_v59_us_equities_z1_research"||
           eq.series_id!=="BOGZ1LM893064105Q"||
           eq.asset_id!=="us_equities"||
           eq.units!=="millions_usd"||
           eq.fresh_for_research!==true||
           eq.validated_for_live_scoring!==false||
           eq.official_asset_score!==null||
           !Number.isFinite(eq.latest_market_value_trillions_usd)||
           !fresh(eq.generated_at,8))throw Error("invalid source");
        line(target,"p","美股官方 Z.1 公司股权市场价值存量："+
          eq.latest_market_value_trillions_usd.toFixed(3)+" 万亿美元；"+
          eq.latest_observation_period+" 期末。包含非上市股权和多个部门；"+
          "不是标普500市值、盈利或可投资回报。","muted");
        const p=document.createElement("p");
        const a=line(p,"a","查看美联储公司股权原始系列");
        a.href="https://fred.stlouisfed.org/series/BOGZ1LM893064105Q";
        a.target="_blank";a.rel="noopener noreferrer";target.append(p);
      }catch{line(target,"p","Z.1 原始报告不可用或验证异常，不展示未经核实的数值。","insights-warning");}
    }
    if(verified.bitcoin?.observed){
      try{
        const btc=await read("../data/asset-compass-bitcoin-chain-v59.json");
        if(btc.report_type!=="asset_compass_v59_bitcoin_mainnet_issuance_research"||
           btc.asset_id!=="bitcoin"||btc.network!=="bitcoin_mainnet"||
           btc.checkpoint_distance_blocks!==1008||
           btc.validated_for_live_scoring!==false||
           btc.official_asset_score!==null||
           !Number.isInteger(btc.observed_tip?.height)||
           !Number.isFinite(btc.nominal_subsidy_to_tip_btc)||
           btc.nominal_subsidy_to_tip_btc>21000000||
           !fresh(btc.observed_tip.block_timestamp,2)||
           !fresh(btc.generated_at,8))throw Error("invalid source");
        line(target,"p","比特币实际区块高度："+btc.observed_tip.height+
          "；按共识减半规则计算的名义累计补贴："+
          btc.nominal_subsidy_to_tip_btc.toLocaleString("en-US",{maximumFractionDigits:8})+
          " BTC。非实际流通量、UTXO供给、ETF持仓或投资回报；尚未交叉验证独立全节点。","muted");
        const p=document.createElement("p");
        const a=line(p,"a","查看比特币区块来源");
        a.href="https://blockstream.info/";
        a.target="_blank";a.rel="noopener noreferrer";target.append(p);
      }catch{line(target,"p","比特币源报告不可用或区块核验失败，不展示未经核实的数值。","insights-warning");}
    }
    line(target,"p","来源存在并不等于交易因子独立、历史首发时间已验证或可以发布0–100投资评分。","insights-warning");
  })().catch(()=>warning("V59 数据读取失败，研究状态未知，禁止推断或展示资产评分。"));
})();
