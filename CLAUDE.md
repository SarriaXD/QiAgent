# CLAUDE.md

## Platform
- Deployment target: iOS 26.0
- Swift: 6.3 (strict concurrency enabled)
- Package manager: SPM only
- Xcode: 26.3+

## Build
- Scheme: QiAgent
- Use XcodeBuildMCP tools (never raw xcodebuild in shell)
- Default simulator: iPhone 17 Pro

## Concurrency
- Prefer @MainActor on UI-facing types (Views, ViewModels with @Observable)
- Use `nonisolated` deliberately, document why
- Mark types crossing concurrency boundaries as Sendable
- Use @concurrent only when explicitly needed for parallel execution
- Never use @unchecked Sendable to silence warnings without comment explaining why

## Build & Test
- Use Swift Testing (@Test, #expect) for new tests
- XCTest only for legacy/UI tests

## Do NOT
- Modify *.pbxproj (human-managed)
- Touch Storyboards/XIBs (legacy)
- Edit *.generated.swift
- Use ObservableObject (use @Observable instead)
- Use NavigationView (use NavigationStack)
- Use Combine (use async/await + Observation)
- Introduce any third-party dependencies (Apple frameworks only)

---

## Project: 端侧 AI 记事本 (QiAgent)

### 目标
iOS 原生应用,用户用语音或文本描述自己做了什么,**端侧 LLM** 自动整理成结构化条目,用户确认后保存。所有数据和 AI 推理完全本地,不联网。

### 技术栈
- **UI**: SwiftUI + Observation
- **持久化**: SwiftData
- **AI**: Foundation Models framework (`LanguageModelSession`, `@Generable`, `Tool`)
- **语音**: Speech framework (`SFSpeechRecognizer`, 本地识别)
- **用户可见文案**: 中文

### 核心架构原则

#### AI 输出走 Generable
所有 AI 生成的草稿用 `@Generable` struct 定义,不解析自由文本。

#### 反驳循环复用同一 session
用户对草稿提出修改意见时,在同一 `LanguageModelSession` 上继续 prompt,不新建 session。

#### 历史记忆三层策略
3B 模型上下文有限,**绝不能**把全部历史塞进 prompt:
1. **类别列表**: 始终注入(很小)
2. **最近少量条目**: 始终注入,提供风格参考
3. **按需查询**: 模型通过 Tool 主动按关键词检索更多历史

不做向量 RAG。SwiftData `#Predicate` 文本匹配足够。

#### 字段级确认,不做字符级 diff
DraftView 把 Generable 的每个字段以可编辑卡片/芯片呈现。AI 重做后变化字段 UI 高亮。

#### AI 只管新增,不改旧条目
草稿 AI 流程仅用于新增。已有条目的编辑/删除走普通 UI。

#### confidence 字段对外可见
AI 草稿必须包含置信度字段(high/medium/low)。low 时 UI 高亮提示用户核对。

#### 多事件输入只取主要一件
用户输入含多件事时,AI 选最主要的一件整理,不自动拆条。

### 核心流程

#### 输入 → 草稿
1. 用户录音(按住录音、松开停止)或打字
2. 语音走 `SFSpeechRecognizer` 本地识别
3. 构造 system prompt(注入类别 + 最近条目)+ 用户原文
4. `streamResponse(generating: ...)` 流式生成,UI 字段实时填充

#### 草稿确认循环
| 用户操作 | 行为 |
|---|---|
| 点「保存」 | 写入 SwiftData,关闭 |
| 直接编辑某字段 | 不经过 AI,直接采纳 |
| 输入纠正(语音/文字) | 同一 session 续写,变化字段高亮 |
| 点「丢弃」 | 销毁 session,关闭 |

### System Prompt 设计要点
- 注入已有类别列表
- 注入最近少量历史条目作为风格参考
- 优先复用已有类别,实在不合适才建议新建
- summary 简洁,不复述用户原话
- 多事件输入只整理最主要的一件
- 信息不足时如实记录,confidence 填 low
- 对分类拿不准时调用历史查询 Tool
- 不做事实判断或道德评价,只忠实整理

### 页面构成
| 页面 | 职责 |
|---|---|
| HomeView | TabView: 录入 / 历史 / 设置 |
| InputView | 大语音按钮 + 文本输入 + 提交 |
| DraftView | 字段卡片化,逐字段可编辑;底部:[丢弃] [继续聊聊] [保存];low confidence 视觉提示 |
| EntryListView | 按日期分组,类别筛选,搜索 |
| EntryDetailView | 完整查看 + 编辑 + 删除 |
| SettingsView | 类别管理(增删改)、JSON 导出 |

### 分阶段开发计划

严格按 Phase 0→6 顺序,每个 Phase 完成跑模拟器验收再进下一阶段。

#### Phase 0: 环境验证
- [ ] 最小 demo:一个按钮调用 LanguageModelSession 输出固定 Generable 类型
- 验收:确认 Xcode / macOS / 设备版本能跑通

#### Phase 1: 数据骨架(无 AI)
- [ ] 工程脚手架,SwiftData 初始化
- [ ] 数据模型 + 首启插入预置类别(工作、学习、运动、饮食、社交、娱乐、家庭、心情)
- [ ] EntryListView + EntryDetailView 纯 CRUD
- [ ] 简单文本输入页(直接写入,不经 AI)
- 验收:纯手动添加、查看、编辑、删除条目可用

#### Phase 2: 语音转文字
- [ ] SpeechRecognizer 封装,权限请求
- [ ] 按住录音 / 松开识别 / 显示转写
- [ ] 转写后允许编辑再保存
- 验收:中文语音稳定转写,无网络也能用

#### Phase 3: AI 草稿生成(单次)
- [ ] PromptBuilder:注入类别 + 最近条目
- [ ] AgentService 封装 LanguageModelSession + streamResponse
- [ ] 定义 EntryDraft 的 Generable 类型(满足 4.1 / 4.6)
- [ ] DraftView:字段卡片化,流式填充,可手动编辑保存
- 验收:输入「今天跑步 5 公里」能生成合理 draft

#### Phase 4: 反驳循环
- [ ] DraftView 增「继续聊聊」入口(语音/文字)
- [ ] 同一 session 续 prompt
- [ ] 前后版本对比,变化字段高亮
- 验收:用户说「分类错了应该是社交」,draft 能更新且高亮变化

#### Phase 5: 历史记忆 + Tool
- [ ] 实现历史查询 Tool(关键词匹配 SwiftData)
- [ ] 系统提示中加入 Tool 使用说明
- [ ] 验证模型在分类边界情况主动调用 Tool
- 验收:类似活动延续历史分类

#### Phase 6: 打磨
- [ ] 列表筛选 / 搜索
- [ ] 类别管理 UI
- [ ] JSON 导出
- [ ] 单元测试覆盖 AgentService 和 Tool

### 验收标准
- 完全离线全功能可用
- 95% 常规输入 3 秒内拿到 draft
- 用户拒绝后 80% 以上纠正能在一次反驳后修正
- 分类延续准确率 >70%
- 数据持久化无丢失,删除/编辑实时生效

### 工程约束
- AgentService 和 Tool 设计成可单测(依赖通过初始化注入,不要全局单例)
- 数据结构、字段命名、文件目录、代码组织由 Claude Code 自由决定,只要满足上述架构原则
