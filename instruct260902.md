# HappaUni 答题功能开发说明

> 记录日期：2026-09-02
> 状态：需求已确认，待开发实现。

## 1. 目标

为 HappaUni 增加以 Markdown 试卷为核心的答题功能，并支持把普通 PDF 或照片中的试题转换成可答题的试卷 Markdown。

用户打开一个 `.md` 文件时，应用必须先检测该文件是否符合本说明定义的试卷格式：

- 校验通过：直接进入答题模式。
- 校验失败：保留普通 Markdown 阅读能力，并显示格式不符合的具体原因；不得进入答题模式。

每个 `.md` 文件代表一套独立试卷。每套试卷在其文件目录下保存一份独立 JSON 日志，用于记录练习历史和未完成进度。

## 2. 支持的题型与判分规则

| `type` | 题型 | 作答方式 | 判分规则 |
| --- | --- | --- | --- |
| `single` | 单选题 | 选择一个选项 | 用户答案与标准答案一致即正确。 |
| `multiple` | 多选题 | 选择一个或多个选项 | 必须与标准答案的选项集合完全一致；少选或多选均为错误。 |
| `blank` | 填空题 | 输入文本 | 提交后显示参考答案；由用户手动点击“答对”或“答错”确认。 |
| `true_false` | 判断题 | 选择“正确”或“错误” | 用户答案与 `true` / `false` 标准答案一致即正确。 |

标准答案缺失时，题目仍可答：系统仅记录用户答案、作答时间与耗时，`isCorrect` 保持 `null`，不显示对错且不纳入正确率。

## 3. 标准试卷 Markdown 格式

### 3.1 文档头

```md
---
title: 示例试卷
version: 1
---
```

- `title`：必填，试卷名称。
- `version`：必填，当前固定为整数 `1`，用于以后格式迁移。

### 3.2 题目格式

每题必须使用二级标题 `## Qxxx` 开始，题目 ID 在同一份试卷中必须唯一。

```md
## Q001
type: single
question: 下列哪项是正确答案？
options:
  - A. 选项一
  - B. 选项二
  - C. 选项三
answer: B
explanation: B 符合题意。

## Q002
type: multiple
question: 请选择所有正确项。
options:
  - A. 选项一
  - B. 选项二
  - C. 选项三
answer: [A, C]
explanation: A、C 都正确，少选或多选均判错。

## Q003
type: blank
question: HappaUni 的名称是 ______。
answer: HappaUni
explanation: 参考答案为 HappaUni。

## Q004
type: true_false
question: 多选题必须完全匹配才算正确。
answer: true
explanation: 多选少选、多选均判错。

## Q005
type: single
question: 此题原始资料未提供标准答案。
options:
  - A. 选项一
  - B. 选项二
  - C. 选项三
answer: null
explanation: null
```

### 3.3 格式校验

必须逐题校验并汇总错误，至少覆盖：

1. 文档头是否包含 `title` 和 `version: 1`。
2. 题目 ID 是否符合 `Q` 加数字的格式，且是否重复。
3. 每题是否包含 `type`、`question`、`answer`、`explanation` 字段。
4. `single` / `multiple` 是否具备非空 `options`；所有选项标识是否唯一。
5. `single` 的非空 `answer` 是否是有效单项选项标识。
6. `multiple` 的非空 `answer` 是否为有效且不重复的选项标识数组。
7. `true_false` 的非空 `answer` 是否仅为 `true` 或 `false`。
8. `blank` 可以有答案或 `null`；有答案时只作为展示参考答案，不自动文本判分。

## 4. 答题流程与界面

1. 用户打开格式有效的试卷 Markdown 后，进入答题模式。
2. 按 Markdown 内题目顺序展示；一屏只答一题。
3. 显示当前题号、总题数、答题进度和本题计时。
4. 用户提交当前题后：
   - 有标准答案的单选、多选、判断题：立即显示正确/错误、标准答案和解析。
   - 填空题：立即显示参考答案与解析，并要求用户点选“答对”或“答错”；确认后才可进入下一题。
   - `answer: null` 的题：仅显示“已记录答案，原资料未提供标准答案”；可进入下一题。
5. 每题判定或记录后立即持久化当前进度，保证中断后可恢复。
6. 用户退出后再次打开同一试卷：检测最近一次未完成练习，并提供“继续上次练习”入口；从该尝试的 `currentQuestionId` 继续。
7. 完成最后一题后展示完成页：
   - 总题数、已判定题数、正确数、错误数、未判定数、总耗时。
   - 正确率饼状图。
   - “仅重做错题”按钮。
   - “重新开始”按钮。
8. “仅重做错题”应基于最近一份已完成尝试中 `isCorrect == false` 的题目创建新的练习记录；原始题目顺序不变。

## 5. 正确率与异常题目

- 正确率 = `正确题数 / 已判定题数`。
- `answer: null` 的题和未完成手动判定的填空题不计入正确率分母。
- 完成页对这类题单独显示“已记录、待人工评阅”的数量。
- 若一套试卷没有任何可判定题目，饼状图显示空状态和“暂无可计算正确率”。

## 6. 日志文件设计

### 6.1 文件位置与命名

日志与试卷保存在同目录，使用试卷文件名衍生：

```text
示例试卷.md
示例试卷.quiz-log.json
```

不得把所有试卷记录混入同一份总日志。日志必须保留历史练习记录，不覆盖旧尝试。

### 6.2 JSON 结构

```json
{
  "schemaVersion": 1,
  "examId": "stable-id-derived-from-exam-path",
  "examPath": "示例试卷.md",
  "attempts": [
    {
      "attemptId": "UUID",
      "mode": "full",
      "sourceAttemptId": null,
      "startedAt": "2026-09-02T10:30:00.000Z",
      "completedAt": null,
      "currentQuestionId": "Q002",
      "questionOrder": ["Q001", "Q002", "Q003"],
      "answers": [
        {
          "questionId": "Q001",
          "userAnswer": "B",
          "isCorrect": true,
          "answeredAt": "2026-09-02T10:30:12.000Z",
          "durationMs": 12000,
          "needsRedo": false,
          "selfReviewed": false
        }
      ]
    }
  ]
}
```

字段约定：

- `mode`：`full` 或 `wrong_only`。
- `sourceAttemptId`：错题重做时填写来源练习 ID；完整练习为 `null`。
- `userAnswer`：单选/判断为选项值，多选为选项数组，填空为用户输入文本。
- `isCorrect`：`true`、`false` 或 `null`；无标准答案时必须为 `null`。
- `needsRedo`：仅 `isCorrect == false` 时为 `true`，其他情况为 `false`。
- `selfReviewed`：仅填空且用户已手动判定时为 `true`。
- 日期一律使用 ISO 8601 UTC 字符串，耗时一律使用毫秒整数。

## 7. PDF / 照片导入与 MinerU 转换

目标是把普通 PDF 或照片转换为符合第 3 节格式的试卷 Markdown。

### 7.1 流程

```text
PDF / 照片
  → MinerU 文档解析
  → Markdown / JSON 中间结果
  → 试题结构识别
  → 转换预览与人工校验
  → 保存为标准试卷 .md
  → 使用答题功能打开
```

### 7.2 转换器职责

1. 从 MinerU 输出中识别题号、题干、选项、答案、解析和跨页内容。
2. 自动映射为 `single`、`multiple`、`blank`、`true_false`。
3. 输出第 3 节定义的试卷 Markdown。
4. 对无法可靠识别的字段标记为待人工确认，尤其包括：
   - 图片模糊或 OCR 不确定。
   - 题干、选项或答案跨页断裂。
   - 题型无法确定。
   - 原资料没有答案/解析。
   - 表格题、复杂公式题、图片选择题。
5. 若原材料没有标准答案或解析，写入：

```md
answer: null
explanation: null
```

6. 转换预览页需显示：识别题目数量、待确认项、重复题号、格式错误和缺少答案项；用户确认或编辑后才能保存为正式试卷。

### 7.3 MinerU 源码改造边界

- 保留 MinerU 原有的 PDF/图片解析能力。
- 在 MinerU 输出之后增加 HappaUni 专用的“试卷结构化转换器”，避免将答题业务逻辑混入底层 OCR/版面解析模块。
- 转换器输出应稳定、可测试，且只依赖 MinerU 的 Markdown/JSON 中间结果。
- HappaUni 侧负责导入、人工校验、保存 Markdown、答题和日志；MinerU 侧负责材料解析与结构化转换。

## 8. 数据安全与兼容性

- 不删除或重写历史 `attempts`。
- 写入 JSON 时使用安全写入策略，避免应用中断造成日志损坏。
- Markdown 或 JSON 解析失败时保留原文件，显示可理解的错误信息。
- 题库格式升级时，通过 `version` 与 `schemaVersion` 进行兼容迁移。
- 题目 ID 是关联历史答题记录的稳定键；编辑试卷时避免无意义地更改已有题目 ID。

## 9. 验收清单

- [ ] 有效试卷 Markdown 打开后进入答题模式。
- [ ] 无效 Markdown 显示明确校验错误，不进入答题模式。
- [ ] 单选、完全匹配多选、填空人工判定、判断题均可完成练习。
- [ ] 含 `answer: null` 的题目可记录答案但不影响正确率。
- [ ] 中途退出后可恢复到最近一次未完成练习的当前题。
- [ ] 每套试卷只生成同目录的一份独立 `.quiz-log.json`，并保留所有历史尝试。
- [ ] 完成页正确率以饼状图呈现，且正确率计算忽略未判定题。
- [ ] 可以基于最近一次完成练习仅重做错题。
- [ ] PDF/照片经 MinerU 导入后可预览、校验、人工修订，并导出为标准试卷 Markdown。
