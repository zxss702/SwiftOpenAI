# 决策记录

## 将 swift-syntax 从 602.0.0 降级到 601.0.1
- 决策主题：依赖版本兼容性调整
- 结论：将 swift-syntax 从 602.0.0 降级到 601.0.1
- 背景：swift-syntax 602.0.0 与 Xcode 16 默认工具链存在兼容性问题
- 影响范围：Package.swift, Package.resolved
- 提交记录：158ca6b

## 使用 Task.detached 修复并发隔离问题
- 决策主题：流处理并发隔离修复
- 结论：将 Task 改为 Task.detached，避免在 @MainActor 上下文中继承不必要的 actor 隔离
- 背景：流处理中出现并发警告
- 影响范围：Sources/SwiftOpenAI/Streaming/StreamingSupport.swift
- 提交记录：3120f51
