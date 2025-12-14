# QinLink

一个使用 Zig 语言实现的高性能 SD-WAN 解决方案。

## 🚀 特性

- ⚡ **零开销抽象**: 编译时优化,无运行时开销
- 🔒 **内存安全**: 无 GC,显式内存管理
- 🎯 **类型安全**: 编译时错误检测
- 📦 **极小体积**: 预估 <2MB 二进制
- 🌍 **跨平台**: 一键交叉编译

## 📋 要求

- Zig 0.16.0 或更高版本

## 🛠️ 快速开始

### 构建项目

```bash
# 运行测试
zig build test

# 构建 (开发模式)
zig build

# 构建 (发布模式)
zig build -Doptimize=ReleaseFast
```

## 📁 项目结构

```
qinlink/
├── src/
│   ├── lib/           # 基础设施层
│   │   ├── error.zig  # 错误处理
│   │   ├── utils.zig  # 工具函数
│   │   ├── logger.zig # 日志系统
│   │   ├── safe.zig   # 线程安全数据结构
│   │   └── socket.zig # Socket 抽象
│   ├── protocol/      # 协议层
│   ├── network/       # 网络设备层
│   ├── switch/        # Switch 服务器
│   └── access/        # Access 客户端
├── build.zig          # 构建脚本
└── README.md
```

## 🤝 贡献

本项目遵循 Zig 编码规范和最佳实践:

1. 使用 `snake_case` 命名
2. 添加文档注释 (`///`)
3. 编写单元测试
4. 显式错误处理

## 📄 许可证

GPL 3.0

---

**GitHub**: https://github.com/iqingba/qinlink  
**状态**: 🟢 活跃开发中
