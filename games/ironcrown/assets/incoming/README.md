# incoming：所有者上传的待核对素材

这里放所有者在自己电脑上从 itch.io 等处下载后上传的 **CC0** 素材原件，等我核对许可与内容后导入。
已处理完的（A.1「人物（一）」用到的 Universal Base Characters 男性底模、Universal Animation Library 1 / 2）已经移走：模型和贴图进了 `../../godot/assets/characters/`，动画库原包放在 `../source/quaternius/`。

- 只放 CC0 的免费版文件（itch.io 上标着「Standard / 标准」的），不放付费版。
- 单个文件不超过 25 MB（GitHub 网页上传的限制）；一次提交的总量也别太大，分批传。
- 导入后原件会清掉，只留游戏里实际用到的部分。这个目录不在 Godot 工程内，不会进网页导出。
- 来源、许可、下载日期记录在 `../SOURCES.md`。
