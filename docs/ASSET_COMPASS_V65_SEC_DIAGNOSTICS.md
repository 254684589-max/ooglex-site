# V65 | SEC 回填失败诊断及真实 XML 结构修正

V64 GitHub Actions run 45567887072 / job 139047225911：离线通过，七份申报真实下载/解析全部 ValueError，0/21 月成功。旧日志只保留异常类，无法确定是下载媒体类型、XML字段路径、还是参考值核对所致。不得声称已查明唯一根因。

官方 SEC 展示文件 https://www.sec.gov/Archives/edgar/data/1100663/000207169126008193/xslFormNPORT-P_X01/primary_doc.xml 核对 TLT Series S000004360 / Class C000012090、报告期 2026-02-28、B.5 三个月总回报。另两份缺值申报 accession 000175272425011820 与 000207169126001287 的官方索引搜索可核对为同一 TLT series，分别对应2024-11-30及2025-11-30，但未取得其回报值，仍保留缺失。

本次继续同一 V63/V64 管道：将身份/报告期限定到 formData/genInfo，将收益限定到 formData/fundInfo/returnInfo/monthlyTotReturns；允许已声明的通用纯文本/二进制媒体类型，仍必须通过严格 XML 结构与基金身份核对，HTML错误页一律拒绝。记录下载、XML身份、参考数值核验阶段和受控错误原因；403/429立即停止，剩余标记未尝试，不绕过。完整性检查仍必须21/21，不伪造原始文件或补零。

新增针对重复 header seriesId、Part A 错误身份及 HTML 错误页的测试。原始 XML 尚待下一次 CI 证实。15个月网页核对不是21个月入库。不得降低V60/V61 PIT、成本核算及正式评分门禁。未部署。
