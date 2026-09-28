# 编码规范

> 团队代码风格和编程约束。所有开发者必须遵守。

## 通用规范

### 命名约定
- 变量、函数: (待定义)
- 类、接口: (待定义)
- 常量: (待定义)
- 文件: (待定义)

### 代码风格
- 缩进: (待定义)
- 行宽: (待定义)
- 引号: (待定义)
- 分号: (待定义)

### 注释规范
- 必须注释的场景: (待定义)
- 注释格式: (待定义)

## 语言特定规范

### TypeScript/JavaScript
(待定义)

### Python
(待定义)

### Java
(待定义)

## Git 规范

### 分支命名
```
<type>/<description>
```

### Commit 信息
```
<type>: <description>

[optional body]
```

### Code Review 要求
- 至少一人 approved
- CI 通过
- 无 merge conflicts

## 禁止事项

- [ ] 禁止直接 push 到 main/master 分支
- [ ] 禁止在生产代码中保留 console.log/print 调试语句
- [ ] 禁止绕过类型检查
- [ ] 禁止提交大型二进制文件