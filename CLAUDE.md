# Kommand — AI Agent Instructions

## Продукт
Kommand — веб-приложение для управления производством и операциями.

## Стек
- Ruby on Rails
- Stimulus JS
- Turbo Frames (Hotwire)
- Tailwind CSS
- Flowbite HTML (не React версия)
- Figma MCP для чтения дизайна

## Дизайн-система

### Цвета
- primary: #1c64f2 (primary/600)
- primary-dark: #1a56db (primary/700)
- primary-darker: #1e3a8a (primary/800)
- background: #FAFAF9 (stone/50)
- text-primary: #1C1917 (stone/900)
- text-secondary: #78716C (stone/500)
- border: #E7E5E4 (stone/200)
- success: green палитра
- error: red палитра
- warning: amber палитра

### Типографика
- Шрифт: Inter (sans-serif)
- text-xs: 12px / font-normal
- text-sm: 14px / font-medium (основной UI текст)
- text-base: 16px / font-normal
- text-lg: 18px / font-semibold
- text-xl: 20px / font-bold
- text-2xl: 24px / font-medium
- text-3xl: 30px / font-semibold

### Скругления
- rounded-md: 6px
- rounded-lg: 8px
- rounded-xl: 12px
- rounded-2xl: 16px

### Отступы
Шкала: 0, 2, 4, 6, 8, 12, 16, 20, 24, 40

### Таблицы
- ag-row-height standard: 42px
- ag-row-height compact: 28px

### Кнопки — состояния и стили
- default: primary/600 `#1c64f2`
- hover: primary/700 `#1a56db`
- active: primary/800 `#1e3a8a` (только пока зажата мышь)
- focus: `focus:outline-none` — без смены цвета, без ring
- shadow: `0px 6px 16px 0px rgba(28, 100, 242, 0.20)`

Tailwind классы: `bg-[#1c64f2] hover:bg-[#1a56db] active:bg-[#1e3a8a] focus:outline-none shadow-[0px_6px_16px_0px_rgba(28,100,242,0.20)]`

### ProfilePic — одиночный аватар
- Компонент показывает ОДИН аватар, не группу и не стек
- Locals: `src:` (image URL), `size:` (`:sm` | `:md` | `:lg`), `shape:` (`:circle` | `:square`)
- `:circle` → `rounded-full`
- `:square` → `rounded-xl` (для sm: `rounded-md`)
- Никакого overlap, никакого overflow "+X", никакого стека
- Статичный компонент — нет hover, focus, active состояний

### Logo — логотип Kommand
- Компонент содержит точные SVG экспорты из Figma — НЕ генерировать иконку самостоятельно
- Locals: `variant:` (`:light` | `:dark`), `size:` (`:sm` | `:lg`)
- Варианты из Figma: sm light (121×24), sm dark (121×24 белый текст), lg light (161×32)
- SVG включает иконку + wordmark единым файлом — не разделять на части
- Статичный компонент — нет hover, focus, active состояний
- Бренд-цвета иконки (#2DD4C0, #FA7186, #FBBF23, #E879F9, #1D96F5) — не менять на палитру UI

## Правила генерации компонентов

### Обязательно
- Компоненты — HTML + Tailwind CSS, совместимые с Rails ERB шаблонами
- Интерактивность через Stimulus контроллеры (не React, не Alpine)
- Динамические обновления через Turbo Frames
- Используй Flowbite HTML классы где возможно
- Используй цвета только из палитры выше
- В конце файла добавляй демо со всеми вариантами компонента

### Состояния
Добавляй только те состояния которые есть в Figma макете — не придумывай лишних

### Иконки
Используй Heroicons SVG inline

### Inline style vs Tailwind классы
- Все визуальные свойства задавать через Tailwind классы, НЕ через inline `style=""`
- Inline `style=""` допускается ТОЛЬКО для `font-family` (из-за кавычек в значении, например `font-family:Inter,ui-sans-serif,system-ui,sans-serif`)
- **НИКОГДА** не дублировать в inline `style=""` свойства которые заданы через Tailwind классы — inline style перебивает hover/active/focus по CSS-специфичности
- Если свойство имеет hover/active/focus вариант — оно ОБЯЗАНО быть только в Tailwind классах
- Плавные переходы между состояниями: добавлять `transition-colors duration-150` к элементам с hover/active состояниями

### Запрещено
- Не использовать React, Vue или любой JS фреймворк
- Не хардкодить данные внутри компонента
- Не создавать новые цвета вне палитры
- Не добавлять состояния и варианты которых нет в макете
- Не добавлять focus ring / focus outline если не указано явно
- Не добавлять scale / transform если не указано явно
- НЕ генерировать SVG логотип самостоятельно — только использовать готовый из файла

## Структура файлов Rails
```
/app
  /views
    /components    ← ERB партиалы компонентов
  /javascript
    /controllers   ← Stimulus контроллеры
```

## Preview Server
- Запуск: `ruby preview_server.rb` из корня проекта
- Сервер на Sinatra, рендерит все `_*.erb` компоненты с демо
- Tailwind CSS генерируется автоматически при старте (safelist из сканирования ERB файлов)
- URL: http://localhost:4567
- Кнопка "Regenerate CSS" — пересборка без перезапуска

## Как работать с Figma
1. Получаешь ссылку на компонент из Figma
2. Читаешь дизайн через Figma MCP
3. Извлекаешь точные токены — цвета, размеры, отступы
4. Генерируешь HTML + Tailwind строго по токенам
5. Если нужна интерактивность — добавляешь Stimulus контроллер

### Важно при чтении Figma
- Ссылка может вести на фрейм целиком — фокусируйся только на компоненте из задачи
- Если в фрейме несколько компонентов — читай только тот, название которого совпадает с задачей
- Не генерируй варианты и состояния которых нет в этом компоненте
- Векторные логотипы и сложные иконки — запрашивать SVG вручную через "Copy as SVG" в Figma
