# 领域文档

工程类技能在探索本仓库代码时应如何消费领域文档。

## 探索前先读

- 根目录的 **`GLOSSARY.md`**
- **`docs/adr/`**：阅读与当前工作区域相关的 ADR

如果这些文件不存在，**静默继续**。不要提示缺失，也不要主动建议创建。`/domain-modeling` 技能（经由 `/grill-with-docs`、`/improve-codebase-architecture` 到达）会在术语或决策实际确定时惰性创建它们。

## 文件结构（single-context）

```
/
├── GLOSSARY.md
├── docs/adr/
│   ├── 0001-….md
│   └── 0002-….md
├── advanced_attack/
├── save_equipment_slots_fix/
├── scythe/
└── winter_feast_clean/
```

## 使用词汇表的术语

当输出需要命名一个领域概念时（issue 标题、重构方案、假设、测试名），使用 `GLOSSARY.md` 定义的术语，不要漂移到词汇表明确避免的同义词。

如果所需概念尚不在词汇表中，这是一个信号：要么你在发明项目不使用的语言（重新考虑），要么存在真实缺口（记录下来，交给 `/domain-modeling`）。

## 标记 ADR 冲突

如果输出与现有 ADR 矛盾，显式指出而不是静默覆盖：

> _与 ADR-0007 矛盾，但值得重新讨论，因为……_
