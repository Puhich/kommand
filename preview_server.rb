# ─── Build mode detection (before Sinatra loads) ────────────────────────────
BUILD_MODE = ARGV.include?('--build')
BUILD_OUTPUT = BUILD_MODE ? File.expand_path(ARGV[ARGV.index('--output')&.+(1)] || 'docs', __dir__) : nil

# Strip our flags so Sinatra doesn't choke on them
ARGV.reject! { |a| a == '--build' || a == '--output' || (!a.start_with?('-') && ARGV[ARGV.index(a).to_i - 1] == '--output') rescue false }

unless BUILD_MODE
  require 'sinatra'
  set :port, 4567
  set :bind, 'localhost'
end

require 'erb'
require 'cgi'
require 'json'
require 'fileutils'

# ─── Configuration ───────────────────────────────────────────────────────────
COMPONENTS_PATH = File.expand_path('app/views/components', __dir__)
CLAUDE_MD_PATH  = File.expand_path('CLAUDE.md', __dir__)
PREVIEW_CSS     = File.expand_path('preview.css', __dir__)
TAILWIND_INPUT  = File.expand_path('.tailwind-input.css', __dir__)
TAILWIND_CONFIG = File.expand_path('.tailwind-safelist.txt', __dir__)

# ─── Rails-like polyfills ────────────────────────────────────────────────────
class String
  def html_safe;  self; end
  def present?;   !nil? && !empty?; end
  def presence;   present? ? self : nil; end
  def blank?;     !present?; end
end

class NilClass
  def present?;  false; end
  def presence;  nil; end
  def html_safe; ''; end
  def blank?;    true; end
end

class Symbol
  def present?; true; end
  def presence; self; end
  def blank?;   false; end
end

class TrueClass
  def present?; true; end
  def blank?;   false; end
end

class FalseClass
  def present?; false; end
  def blank?;   true; end
end

# ─── Tailwind CSS Generation ────────────────────────────────────────────────
def extract_classes_from_components
  classes = Set.new
  Dir.glob(File.join(COMPONENTS_PATH, '_*.erb')).each do |f|
    content = File.read(f)
    content.scan(/class\s*=\s*"([^"]*?)"/m).flatten.each do |cls_str|
      cls_str.split(/\s+/).each { |c| classes << c.strip if c.strip.length > 0 }
    end
    content.scan(/class\s*=\s*'([^']*?)'/m).flatten.each do |cls_str|
      cls_str.split(/\s+/).each { |c| classes << c.strip if c.strip.length > 0 }
    end
    content.scan(/=\s*'([^']{10,})'/).flatten.each do |str|
      str.split(/\s+/).each { |c| classes << c.strip if c.strip.length > 1 }
    end
    content.scan(/=\s*"([^"]{10,})"/).flatten.each do |str|
      next if str.include?('<%')
      str.split(/\s+/).each { |c| classes << c.strip if c.strip.length > 1 }
    end
  end
  classes.select { |c|
    c =~ /\A[a-zA-Z!-]/ &&
    !c.include?('=') && !c.include?('{') && !c.include?('<') && !c.include?('>') &&
    c !~ /\A(https?|mailto|true|false|nil|none|button|span|div|svg|path|xmlns)\z/i
  }.sort
end

def generate_tailwind_css!
  puts "🎨 Scanning components for Tailwind classes..."
  classes = extract_classes_from_components
  safelist_html = File.expand_path('safelist.html', __dir__)
  File.write(safelist_html, %(<div class="#{classes.join(' ')}"></div>\n))
  File.write(TAILWIND_CONFIG, classes.join("\n"))
  puts "   Found #{classes.size} unique classes"

  tw_config = File.expand_path('.tailwind.config.js', __dir__)
  File.write(tw_config, <<~JS)
    module.exports = {
      content: [
        '#{COMPONENTS_PATH}/**/*.erb',
        '#{safelist_html}'
      ],
      theme: {
        extend: {
          fontFamily: {
            sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
          },
        },
      },
    }
  JS

  File.write(TAILWIND_INPUT, "@tailwind utilities;\n")

  puts "🔧 Running Tailwind CLI..."
  tailwind_bin = find_tailwind_bin
  unless tailwind_bin
    puts "❌ Tailwind CLI not found!"
    generate_fallback_css!(classes)
    return false
  end

  cmd = "#{tailwind_bin} -i #{TAILWIND_INPUT} -o #{PREVIEW_CSS} -c #{tw_config} --minify 2>&1"
  puts "   Running: #{cmd}"
  output = `#{cmd}`
  success = $?.success?

  if success
    size_kb = (File.size(PREVIEW_CSS) / 1024.0).round(1)
    puts "✅ Generated preview.css (#{size_kb}KB)"
  else
    puts "❌ Tailwind CLI failed:\n#{output}"
    generate_fallback_css!(classes)
  end
  success
end

def find_tailwind_bin
  %w[tailwindcss].each { |b| return b if system("which #{b} > /dev/null 2>&1") }
  return 'npx tailwindcss' if system('which npx > /dev/null 2>&1')
  local = File.expand_path('node_modules/.bin/tailwindcss', __dir__)
  return local if File.executable?(local)
  nil
end

def generate_fallback_css!(classes)
  puts "⚠️  Generating fallback CSS..."
  css = <<~CSS
    .font-sans, [class*="font-"] { font-family: 'Inter', ui-sans-serif, system-ui, sans-serif; }
    .flex { display: flex; } .inline-flex { display: inline-flex; } .hidden { display: none; } .block { display: block; } .inline-block { display: inline-block; } .grid { display: grid; }
    .flex-col { flex-direction: column; } .flex-row { flex-direction: row; } .flex-wrap { flex-wrap: wrap; }
    .items-center { align-items: center; } .items-start { align-items: flex-start; } .items-end { align-items: flex-end; }
    .justify-center { justify-content: center; } .justify-between { justify-content: space-between; } .justify-start { justify-content: flex-start; } .justify-end { justify-content: flex-end; }
    .shrink-0 { flex-shrink: 0; } .grow { flex-grow: 1; } .flex-1 { flex: 1 1 0%; }
    .gap-0 { gap: 0; } .gap-0\\.5 { gap: 2px; } .gap-1 { gap: 4px; } .gap-1\\.5 { gap: 6px; } .gap-2 { gap: 8px; } .gap-2\\.5 { gap: 10px; } .gap-3 { gap: 12px; } .gap-4 { gap: 16px; } .gap-5 { gap: 20px; } .gap-6 { gap: 24px; } .gap-8 { gap: 32px; } .gap-10 { gap: 40px; }
    .p-0 { padding: 0; } .p-1 { padding: 4px; } .p-2 { padding: 8px; } .p-3 { padding: 12px; } .p-4 { padding: 16px; } .p-5 { padding: 20px; } .p-6 { padding: 24px; }
    .px-1 { padding-left: 4px; padding-right: 4px; } .px-2 { padding-left: 8px; padding-right: 8px; } .px-3 { padding-left: 12px; padding-right: 12px; } .px-4 { padding-left: 16px; padding-right: 16px; } .px-5 { padding-left: 20px; padding-right: 20px; } .px-6 { padding-left: 24px; padding-right: 24px; }
    .py-1 { padding-top: 4px; padding-bottom: 4px; } .py-1\\.5 { padding-top: 6px; padding-bottom: 6px; } .py-2 { padding-top: 8px; padding-bottom: 8px; } .py-2\\.5 { padding-top: 10px; padding-bottom: 10px; } .py-3 { padding-top: 12px; padding-bottom: 12px; } .py-4 { padding-top: 16px; padding-bottom: 16px; }
    .m-0 { margin: 0; } .m-auto { margin: auto; } .mx-auto { margin-left: auto; margin-right: auto; }
    .mt-1 { margin-top: 4px; } .mt-2 { margin-top: 8px; } .mt-3 { margin-top: 12px; } .mt-4 { margin-top: 16px; }
    .mb-1 { margin-bottom: 4px; } .mb-2 { margin-bottom: 8px; } .mb-3 { margin-bottom: 12px; } .mb-4 { margin-bottom: 16px; }
    .ml-1 { margin-left: 4px; } .ml-2 { margin-left: 8px; } .ml-auto { margin-left: auto; } .mr-1 { margin-right: 4px; } .mr-2 { margin-right: 8px; }
    .w-full { width: 100%; } .w-auto { width: auto; } .h-auto { height: auto; } .h-full { height: 100%; } .w-6 { width: 24px; } .h-6 { height: 24px; }
    .min-w-0 { min-width: 0; } .max-w-full { max-width: 100%; }
    #{generate_size_classes(classes)}
    .text-xs { font-size: 12px; line-height: 16px; } .text-sm { font-size: 14px; line-height: 20px; } .text-base { font-size: 16px; line-height: 24px; } .text-lg { font-size: 18px; line-height: 28px; } .text-xl { font-size: 20px; line-height: 28px; } .text-2xl { font-size: 24px; line-height: 32px; } .text-3xl { font-size: 30px; line-height: 36px; }
    .font-normal { font-weight: 400; } .font-medium { font-weight: 500; } .font-semibold { font-weight: 600; } .font-bold { font-weight: 700; }
    .text-white { color: #fff; } .text-black { color: #000; }
    .text-stone-50 { color: #FAFAF9; } .text-stone-100 { color: #F5F5F4; } .text-stone-200 { color: #E7E5E4; } .text-stone-300 { color: #D6D3D1; } .text-stone-400 { color: #A8A29E; } .text-stone-500 { color: #78716C; } .text-stone-600 { color: #57534E; } .text-stone-700 { color: #44403C; } .text-stone-800 { color: #292524; } .text-stone-900 { color: #1C1917; }
    .text-\\[\\#1c64f2\\] { color: #1c64f2; } .text-\\[\\#1a56db\\] { color: #1a56db; }
    .bg-white { background-color: #fff; } .bg-transparent { background-color: transparent; }
    .bg-stone-50 { background-color: #FAFAF9; } .bg-stone-100 { background-color: #F5F5F4; } .bg-stone-200 { background-color: #E7E5E4; } .bg-stone-900 { background-color: #1C1917; }
    .bg-\\[\\#1c64f2\\] { background-color: #1c64f2; } .bg-\\[\\#1a56db\\] { background-color: #1a56db; } .bg-\\[\\#1e3a8a\\] { background-color: #1e3a8a; }
    .hover\\:bg-\\[\\#1a56db\\]:hover { background-color: #1a56db; } .hover\\:bg-\\[\\#1e3a8a\\]:hover { background-color: #1e3a8a; }
    .hover\\:bg-stone-50:hover { background-color: #FAFAF9; } .hover\\:bg-stone-100:hover { background-color: #F5F5F4; }
    .active\\:bg-\\[\\#1e3a8a\\]:active { background-color: #1e3a8a; }
    .focus\\:outline-none:focus { outline: none; }
    .border { border-width: 1px; border-style: solid; } .border-0, .border-none { border: none; }
    .border-stone-200 { border-color: #E7E5E4; } .border-stone-300 { border-color: #D6D3D1; } .border-transparent { border-color: transparent; }
    .rounded { border-radius: 4px; } .rounded-md { border-radius: 6px; } .rounded-lg { border-radius: 8px; } .rounded-xl { border-radius: 12px; } .rounded-2xl { border-radius: 16px; } .rounded-full { border-radius: 9999px; }
    .shadow-sm { box-shadow: 0 1px 2px 0 rgba(0,0,0,0.05); } .shadow { box-shadow: 0 1px 3px 0 rgba(0,0,0,0.1); } .shadow-md { box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); } .shadow-none { box-shadow: none; }
    .shadow-\\[0px_6px_16px_0px_rgba\\(28\\,100\\,242\\,0\\.20\\)\\] { box-shadow: 0px 6px 16px 0px rgba(28,100,242,0.20); }
    .overflow-hidden { overflow: hidden; } .overflow-auto { overflow: auto; }
    .object-cover { object-fit: cover; } .object-contain { object-fit: contain; }
    .cursor-pointer { cursor: pointer; } .cursor-default { cursor: default; }
    .relative { position: relative; } .absolute { position: absolute; } .fixed { position: fixed; }
    .inset-0 { top:0;right:0;bottom:0;left:0; } .top-0 { top:0; } .right-0 { right:0; } .bottom-0 { bottom:0; } .left-0 { left:0; }
    .z-10 { z-index: 10; } .z-20 { z-index: 20; } .z-50 { z-index: 50; }
    .opacity-0 { opacity: 0; } .opacity-50 { opacity: 0.5; } .opacity-100 { opacity: 1; }
    .truncate { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .text-left { text-align: left; } .text-center { text-align: center; } .text-right { text-align: right; }
    .leading-none { line-height: 1; } .leading-tight { line-height: 1.25; } .leading-normal { line-height: 1.5; }
    .leading-\\[1\\.5\\] { line-height: 1.5; } .leading-\\[1\\] { line-height: 1; }
    .transition { transition-property: color,background-color,border-color,box-shadow,transform; transition-duration: 150ms; }
    .transition-colors { transition-property: color,background-color,border-color; transition-duration: 150ms; }
    .transition-all { transition-property: all; transition-duration: 150ms; }
    .duration-150 { transition-duration: 150ms; } .duration-200 { transition-duration: 200ms; }
    .fill-current { fill: currentColor; } .stroke-current { stroke: currentColor; }
    .select-none { user-select: none; }
    .text-\\[14px\\] { font-size: 14px; } .text-\\[12px\\] { font-size: 12px; } .text-\\[13px\\] { font-size: 13px; } .text-\\[16px\\] { font-size: 16px; } .text-\\[10px\\] { font-size: 10px; } .text-\\[11px\\] { font-size: 11px; }
    .leading-\\[20px\\] { line-height: 20px; } .leading-\\[16px\\] { line-height: 16px; } .leading-\\[24px\\] { line-height: 24px; }
    .gap-\\[8px\\] { gap: 8px; } .gap-\\[4px\\] { gap: 4px; } .gap-\\[12px\\] { gap: 12px; } .gap-\\[16px\\] { gap: 16px; } .gap-\\[6px\\] { gap: 6px; } .gap-\\[10px\\] { gap: 10px; } .gap-\\[2px\\] { gap: 2px; }
    .p-\\[8px\\] { padding: 8px; } .p-\\[12px\\] { padding: 12px; } .p-\\[16px\\] { padding: 16px; }
    .px-\\[12px\\] { padding-left:12px;padding-right:12px; } .px-\\[16px\\] { padding-left:16px;padding-right:16px; } .px-\\[8px\\] { padding-left:8px;padding-right:8px; }
    .py-\\[6px\\] { padding-top:6px;padding-bottom:6px; } .py-\\[8px\\] { padding-top:8px;padding-bottom:8px; } .py-\\[10px\\] { padding-top:10px;padding-bottom:10px; } .py-\\[12px\\] { padding-top:12px;padding-bottom:12px; }
    #{generate_arbitrary_classes(classes)}
  CSS
  File.write(PREVIEW_CSS, css)
  size_kb = (css.bytesize / 1024.0).round(1)
  puts "✅ Generated fallback preview.css (#{size_kb}KB)"
end

def generate_size_classes(classes)
  css_lines = []
  classes.each do |c|
    if (m = c.match(/\Asize-\[(\d+)px\]\z/))
      esc = c.gsub('[', '\\[').gsub(']', '\\]')
      css_lines << ".#{esc} { width: #{m[1]}px; height: #{m[1]}px; }"
    elsif (m = c.match(/\Aw-\[(\d+)px\]\z/))
      esc = c.gsub('[', '\\[').gsub(']', '\\]')
      css_lines << ".#{esc} { width: #{m[1]}px; }"
    elsif (m = c.match(/\Ah-\[(\d+)px\]\z/))
      esc = c.gsub('[', '\\[').gsub(']', '\\]')
      css_lines << ".#{esc} { height: #{m[1]}px; }"
    end
  end
  css_lines.join("\n    ")
end

def generate_arbitrary_classes(classes)
  css_lines = []
  classes.each do |c|
    if (m = c.match(/\Abg-\[(#[0-9a-fA-F]{3,8})\]\z/))
      css_lines << ".#{escape_css_class(c)} { background-color: #{m[1]}; }"
    end
    if (m = c.match(/\Atext-\[(#[0-9a-fA-F]{3,8})\]\z/))
      css_lines << ".#{escape_css_class(c)} { color: #{m[1]}; }"
    end
    if (m = c.match(/\Aborder-\[(#[0-9a-fA-F]{3,8})\]\z/))
      css_lines << ".#{escape_css_class(c)} { border-color: #{m[1]}; }"
    end
    if c.start_with?('shadow-[') && c.end_with?(']')
      val = c[8..-2].gsub('_', ' ')
      css_lines << ".#{escape_css_class(c)} { box-shadow: #{val}; }"
    end
    if (m = c.match(/\Ahover:bg-\[(#[0-9a-fA-F]{3,8})\]\z/))
      css_lines << ".#{escape_css_class(c)}:hover { background-color: #{m[1]}; }"
    end
    if (m = c.match(/\Aactive:bg-\[(#[0-9a-fA-F]{3,8})\]\z/))
      css_lines << ".#{escape_css_class(c)}:active { background-color: #{m[1]}; }"
    end
    if (m = c.match(/\Afont-\[(.+)\]\z/)) && !c.match(/\Afont-\[\d/)
      val = m[1].gsub('_', ' ').gsub("'", '')
      css_lines << ".#{escape_css_class(c)} { font-family: #{val}; }"
    end
  end
  css_lines.uniq.join("\n    ")
end

def escape_css_class(cls)
  cls.gsub('\\', '\\\\\\\\').gsub('[', '\\[').gsub(']', '\\]').gsub('#', '\\#')
     .gsub('(', '\\(').gsub(')', '\\)').gsub(',', '\\,').gsub('.', '\\.')
     .gsub('/', '\\/').gsub(':', '\\:').gsub("'", "\\'")
end

# ─── Component Renderer ─────────────────────────────────────────────────────
class ComponentRenderer
  def initialize(locals = {})
    @local_assigns = locals
    locals.each do |k, v|
      instance_variable_set("@#{k}", v)
      define_singleton_method(k) { v } unless respond_to?(k)
    end
  end

  def local_assigns; @local_assigns ||= {}; end

  def render(partial_or_options = nil, locals_or_nothing = {})
    if partial_or_options.is_a?(Hash)
      partial = partial_or_options[:partial]
      locals = partial_or_options[:locals] || {}
    else
      partial = partial_or_options
      locals = locals_or_nothing
    end
    name = partial.to_s.split('/').last
    file = Dir.glob(File.join(COMPONENTS_PATH, "_#{name}*.erb")).first
    return error_tag("Not found: #{partial}") unless file
    template = File.read(file)
    renderer = ComponentRenderer.new(locals)
    renderer.instance_eval { ERB.new(template, trim_mode: '-').result(binding) }
  rescue => e
    error_tag(e.message)
  end

  def image_tag(src, options = {})
    cls = options[:class] || options['class'] || ''
    alt = options[:alt] || options['alt'] || ''
    style = options[:style] || options['style'] || ''
    %(<img src="#{CGI.escapeHTML(src.to_s)}" class="#{CGI.escapeHTML(cls)}" alt="#{CGI.escapeHTML(alt)}" style="#{CGI.escapeHTML(style)}" />)
  end

  def content_tag(tag, content_or_options = nil, options = nil, &block)
    if block_given?
      opts = content_or_options || {}
      content = block.call
    else
      content = content_or_options
      opts = options || {}
    end
    attrs = opts.map { |k, v| %( #{k}="#{CGI.escapeHTML(v.to_s)}") }.join
    "<#{tag}#{attrs}>#{content}</#{tag}>"
  end

  def tag; TagBuilder.new; end
  def concat(str); str.to_s; end
  def capture(&block); block.call.to_s; end
  def get_binding; binding; end

  private
  def error_tag(msg)
    "<span style='color:#dc2626;font-size:12px;background:#fee2e2;padding:4px 8px;border-radius:4px'>#{CGI.escapeHTML(msg)}</span>"
  end
end

class TagBuilder
  def div(content = nil, **attrs, &block); build_tag('div', content, attrs, &block); end
  def span(content = nil, **attrs, &block); build_tag('span', content, attrs, &block); end
  private
  def build_tag(name, content, attrs, &block)
    content = block.call if block_given?
    attr_str = attrs.map { |k, v| %( #{k}="#{CGI.escapeHTML(v.to_s)}") }.join
    "<#{name}#{attr_str}>#{content}</#{name}>"
  end
end

# ─── Logo Renderer ───────────────────────────────────────────────────────────
def render_sidebar_logo
  renderer = ComponentRenderer.new(variant: :dark, size: :sm)
  logo_file = Dir.glob(File.join(COMPONENTS_PATH, '_logo*.erb')).first
  return '<span style="color:white;font-size:13px;font-weight:600">Kommand</span>' unless logo_file
  template = File.read(logo_file)
  renderer.instance_eval { ERB.new(template, trim_mode: '-').result(binding) }
rescue => e
  '<span style="color:white;font-size:13px;font-weight:600">Kommand</span>'
end

# ─── Syntax Highlighting (server-side) ────────────────────────────────────────
def highlight_erb_source(source)
  html = CGI.escapeHTML(source)
  # ERB comments: <%# ... %>  (must be before generic ERB tags)
  html.gsub!(/(&lt;%#.*?%&gt;)/) { %(<span class="hl-comment">#{$1}</span>) }
  # ERB tags: <% ... %> and <%= ... %>
  html.gsub!(/(&lt;%-?=?\s)(.*?)(\s-?%&gt;)/) { %(<span class="hl-erb">#{$1}#{$2}#{$3}</span>) }
  # HTML comments
  html.gsub!(/(&lt;!--.*?--&gt;)/m) { %(<span class="hl-comment">#{$1}</span>) }
  # Strings in double quotes (but not inside our span tags)
  html.gsub!(/(?<!class=)&quot;([^&]*?)&quot;/) { %(&quot;<span class="hl-str">#{$1}</span>&quot;) }
  # HTML tag names: &lt;tag and &lt;/tag
  html.gsub!(/(&lt;\/?)([\w.-]+)/) { %(#{$1}<span class="hl-tag">#{$2}</span>) }
  # Attributes: word= (but not class= inside our span tags)
  html.gsub!(/(?<!\")(?<!\w)([\w-]+)(=)(?=&quot;|&#39;)/) { %(<span class="hl-attr">#{$1}</span>#{$2}) }
  # Tailwind classes: recolor class= values
  html.gsub!(/<span class="hl-attr">class<\/span>=&quot;<span class="hl-str">(.*?)<\/span>&quot;/) {
    %(<span class="hl-attr">class</span>=&quot;<span class="hl-class">#{$1}</span>&quot;)
  }
  html
end

# ─── Demo Rendering ──────────────────────────────────────────────────────────
def render_demo(file)
  template = File.read(file)
  renderer = ComponentRenderer.new(demo: true)
  renderer.instance_eval { ERB.new(template, trim_mode: '-').result(binding) }
rescue => e
  "<div style='color:#dc2626;font-size:12px;padding:6px 10px;background:#fee2e2;border-radius:6px'>Error: #{CGI.escapeHTML(e.message)}<br><pre style='font-size:11px;margin-top:4px'>#{CGI.escapeHTML(e.backtrace&.first(5)&.join("\n") || '')}</pre></div>"
end

# ─── Tokens Parser ───────────────────────────────────────────────────────────
def parse_tokens_from_claude_md
  return {} unless File.exist?(CLAUDE_MD_PATH)
  content = File.read(CLAUDE_MD_PATH)
  tokens = {}

  # Colors — match only within ### Цвета section, one per line
  colors = []
  if (color_section = content[/### Цвета\s*\n(.*?)(?=\n###|\n##|\z)/m, 1])
    color_section.scan(/^- ([^:]+?):\s*(#[0-9a-fA-F]{6})\s*(?:\(([^)]+)\))?/).each do |name, hex, alias_name|
      colors << { name: name.strip, hex: hex, alias: alias_name&.strip }
    end
  end
  tokens[:colors] = colors if colors.any?

  # Typography
  typo = []
  content.scan(/^- (text-\w+):\s*(\d+px)\s*\/\s*(font-\w+)(?:\s*\((.+?)\))?/).each do |cls, size, weight, note|
    typo << { class: cls, size: size, weight: weight, note: note&.strip }
  end
  tokens[:typography] = typo if typo.any?

  # Border radius
  radii = []
  content.scan(/^- (rounded-\w+):\s*(\d+px)/).each do |cls, size|
    radii << { class: cls, size: size }
  end
  tokens[:radii] = radii if radii.any?

  # Spacing
  if (m = content.match(/Шкала:\s*(.+)/))
    tokens[:spacing] = m[1].strip.split(/,\s*/).map(&:strip)
  end

  # Shadows
  if (m = content.match(/shadow:\s*`(.+?)`/))
    tokens[:shadows] = [{ name: 'button', value: m[1] }]
  end

  tokens
end

# ─── CSS Generation on Start ─────────────────────────────────────────────────
puts "\n🚀 Kommand Component Preview Server"
puts "   Components: #{COMPONENTS_PATH}"

unless Dir.exist?(COMPONENTS_PATH)
  puts "❌ Components directory not found: #{COMPONENTS_PATH}"
  exit 1
end

component_count = Dir.glob(File.join(COMPONENTS_PATH, '_*.erb')).size
puts "   Found #{component_count} components"
generate_tailwind_css!

if BUILD_MODE
  # ─── Static Build Mode ──────────────────────────────────────────────────
  puts "📦 Building static site to #{BUILD_OUTPUT}/"
  FileUtils.mkdir_p(BUILD_OUTPUT)

  files = Dir.glob(File.join(COMPONENTS_PATH, '_*.erb')).sort
  @components = files.map do |f|
    name = File.basename(f).sub(/\A_/, '').sub(/\.html\.erb\z/, '').sub(/\.erb\z/, '')
    { name: name, file: f, filename: File.basename(f), demo_html: render_demo(f), source: File.read(f), highlighted: highlight_erb_source(File.read(f)) }
  end
  @tokens = parse_tokens_from_claude_md
  @sidebar_logo = render_sidebar_logo

  # Read the template from __END__ section
  template_data = File.read(__FILE__).split("__END__\n", 2).last
  template_src = template_data.sub(/\A\s*@@index\s*\n/, '')

  # Inline CSS: replace <link href="/preview.css"> with <style>contents</style>
  preview_css = File.exist?(PREVIEW_CSS) ? File.read(PREVIEW_CSS) : ''
  template_src = template_src.gsub(
    '<link href="/preview.css" rel="stylesheet">',
    "<style>\n#{preview_css}\n</style>"
  )

  # Remove regenerate link (not available in static mode)
  template_src = template_src.gsub('href="/regenerate"', 'href="#" onclick="return false"')

  # Render
  b = binding
  html = ERB.new(template_src, trim_mode: '-').result(b)

  File.write(File.join(BUILD_OUTPUT, 'index.html'), html)

  # Copy OG image if it exists
  og_src = File.expand_path('og.png', __dir__)
  if File.exist?(og_src)
    FileUtils.cp(og_src, File.join(BUILD_OUTPUT, 'og.png'))
    puts "   📷 Copied og.png"
  else
    puts "   💡 Place og.png in project root for OG preview image"
  end

  # Copy favicon if it exists
  fav_src = File.expand_path('favicon.svg', __dir__)
  if File.exist?(fav_src)
    FileUtils.cp(fav_src, File.join(BUILD_OUTPUT, 'favicon.svg'))
    puts "   🎨 Copied favicon.svg"
  else
    puts "   💡 Place favicon.svg in project root for favicon"
  end
  cname_file = File.join(BUILD_OUTPUT, 'CNAME')
  unless File.exist?(cname_file)
    # Don't overwrite if user has their own
    puts "   💡 Create #{BUILD_OUTPUT}/CNAME with your domain to enable custom domain"
  end

  size_kb = (File.size(File.join(BUILD_OUTPUT, 'index.html')) / 1024.0).round(1)
  puts "✅ Built index.html (#{size_kb}KB)"
  puts "   Open: file://#{File.join(BUILD_OUTPUT, 'index.html')}"
  exit 0
end

puts "   Starting server at http://localhost:4567\n\n"

# ─── Routes (Sinatra only) ──────────────────────────────────────────────────
unless BUILD_MODE

get '/preview.css' do
  content_type 'text/css'
  File.exist?(PREVIEW_CSS) ? File.read(PREVIEW_CSS) : ''
end

get '/regenerate' do
  generate_tailwind_css!
  redirect '/'
end

get '/' do
  files = Dir.glob(File.join(COMPONENTS_PATH, '_*.erb')).sort
  @components = files.map do |f|
    name = File.basename(f).sub(/\A_/, '').sub(/\.html\.erb\z/, '').sub(/\.erb\z/, '')
    { name: name, file: f, filename: File.basename(f), demo_html: render_demo(f), source: File.read(f), highlighted: highlight_erb_source(File.read(f)) }
  end
  @tokens = parse_tokens_from_claude_md
  @sidebar_logo = render_sidebar_logo
  erb :index
end

end # unless BUILD_MODE

__END__

@@index
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Kommand — Design System</title>
  <meta name="description" content="Kommand Design System — component library and design tokens">
  <meta property="og:title" content="Kommand — Design System">
  <meta property="og:description" content="Component library and design tokens for Kommand">
  <meta property="og:image" content="https://kommand.space/og.png">
  <meta property="og:type" content="website">
  <meta property="og:url" content="https://kommand.space">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:image" content="https://kommand.space/og.png">
  <link rel="icon" type="image/svg+xml" href="favicon.svg">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
  <link href="/preview.css" rel="stylesheet">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Inter', ui-sans-serif, system-ui, sans-serif; background: #FAFAF9; color: #1C1917; -webkit-font-smoothing: antialiased; overflow-y: scroll; }
    body::-webkit-scrollbar { width: 12px; }
    body::-webkit-scrollbar-track { background: #FAFAF9; }
    body::-webkit-scrollbar-thumb { background: #C4C0BD; border-radius: 6px; border: 3px solid #FAFAF9; }
    body::-webkit-scrollbar-thumb:hover { background: #A8A29E; }

    /* ── Sidebar ── */
    .sidebar { position: fixed; left: 0; top: 0; bottom: 0; width: 220px; background: #1C1917; overflow-y: auto; z-index: 10; display: flex; flex-direction: column; }
    .sidebar-logo { display: flex; align-items: center; padding: 20px 16px 16px; border-bottom: 1px solid rgba(255,255,255,0.06); }
    .nav-group { padding: 12px 0; }
    .nav-group-header { display: flex; align-items: center; justify-content: space-between; padding: 6px 16px; cursor: pointer; user-select: none; }
    .nav-group-header:hover .nav-group-label { color: #D6D3D1; }
    .nav-group-label { color: #57534E; font-size: 10px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.08em; }
    .nav-group-arrow { color: #57534E; font-size: 10px; transition: transform 0.2s; }
    .nav-group.collapsed .nav-group-arrow { transform: rotate(-90deg); }
    .nav-group.collapsed .nav-group-items { display: none; }
    .nav-group-items { padding-top: 4px; }
    .nav-item { display: block; padding: 6px 16px 6px 24px; color: #A8A29E; font-size: 12px; font-weight: 500; text-decoration: none; border-left: 2px solid transparent; transition: all 0.1s; }
    .nav-item:hover { color: white; background: rgba(255,255,255,0.04); }
    .nav-item.active { color: white; border-left-color: #1c64f2; background: rgba(28,100,242,0.12); }
    .sidebar-footer { margin-top: auto; padding: 12px 16px; border-top: 1px solid rgba(255,255,255,0.06); }
    .sidebar-footer a { color: #57534E; font-size: 11px; text-decoration: none; font-weight: 500; display: flex; align-items: center; gap: 6px; }
    .sidebar-footer a:hover { color: #A8A29E; }

    /* ── Main ── */
    .main { margin-left: 220px; padding: 28px 36px; }

    /* ── iOS Switcher ── */
    .switcher-wrapper { display: flex; align-items: center; justify-content: space-between; margin-bottom: 24px; }
    .search-input { padding: 6px 12px 6px 32px; font-size: 13px; border: 1px solid #E7E5E4; border-radius: 8px; background: white; color: #1C1917; outline: none; width: 200px; font-family: inherit; transition: border-color 0.1s; height: 36px; }
    .search-input:focus { border-color: #1c64f2; }
    .search-input::placeholder { color: #A8A29E; }
    .search-wrap { position: relative; }
    .search-icon { position: absolute; left: 10px; top: 50%; transform: translateY(-50%); color: #A8A29E; pointer-events: none; }
    .switcher { display: inline-flex; background: #E7E5E4; border-radius: 10px; padding: 3px; gap: 2px; }
    .switcher-btn { padding: 0 20px; font-size: 13px; font-weight: 600; border: none; border-radius: 8px; cursor: pointer; background: transparent; color: #78716C; transition: all 0.1s; user-select: none; font-family: inherit; height: 30px; display: inline-flex; align-items: center; justify-content: center; }
    .switcher-btn.active { background: white; color: #1C1917; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
    .switcher-btn:not(.active):hover { color: #44403C; }

    .page-section { display: none; }
    .page-section.active { display: block; }
    .section-subtitle { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: #A8A29E; margin-bottom: 16px; }

    /* ── Cards ── */
    html { scroll-behavior: smooth; }
    .card { background: white; border: 1px solid #E7E5E4; border-radius: 12px; margin-bottom: 20px; overflow: hidden; transition: border-color 0.15s ease, box-shadow 0.15s ease; scroll-margin-top: 20px; box-shadow: 0 0 0 rgba(0,0,0,0); }
    .card:hover { border-color: #D6D3D1; box-shadow: 0 2px 8px rgba(0,0,0,0.04); }
    .bottom-spacer { height: 60vh; }
    .card-header { padding: 10px 16px; border-bottom: 1px solid #E7E5E4; display: flex; align-items: center; justify-content: space-between; }
    .card-name { font-size: 13px; font-weight: 600; color: #1C1917; }
    .card-file { font-size: 11px; color: #A8A29E; font-family: 'Menlo', 'SF Mono', monospace; }
    .tab-bar { display: flex; gap: 2px; padding: 0 16px; border-bottom: 1px solid #E7E5E4; background: #FAFAF9; }
    .tab { padding: 8px 10px; font-size: 12px; font-weight: 500; color: #78716C; cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -1px; transition: color 0.1s; user-select: none; }
    .tab:hover { color: #1C1917; }
    .tab.active { color: #1c64f2; border-bottom-color: #1c64f2; }
    .preview-area { padding: 28px; min-height: 60px; }
    .preview-stone { background: #FAFAF9; }
    .preview-white { background: white; }
    .preview-dark  { background: #1C1917; }
    .code-wrapper { position: relative; }
    .code-block { background: #1C1917; color: #D6D3D1; font-family: 'Menlo', 'SF Mono', monospace; font-size: 12px; line-height: 1.6; padding: 20px; padding-right: 80px; padding-bottom: 24px; overflow-x: auto; white-space: pre; margin: 0; }
    .code-block::-webkit-scrollbar { height: 12px; }
    .code-block::-webkit-scrollbar-track { background: #1C1917; margin: 0 16px; }
    .code-block::-webkit-scrollbar-thumb { background: #57534E; border-radius: 6px; border: 3px solid #1C1917; }
    .code-block::-webkit-scrollbar-thumb:hover { background: #78716C; }
    /* Syntax highlighting */
    .hl-tag { color: #F87171; }
    .hl-attr { color: #FBBF24; }
    .hl-str { color: #34D399; }
    .hl-erb { color: #A78BFA; }
    .hl-comment { color: #6B7280; font-style: italic; }
    .hl-class { color: #38BDF8; }
    .copy-btn { position: absolute; top: 10px; right: 10px; padding: 5px 10px; font-size: 11px; font-weight: 500; color: #A8A29E; background: #292524; border: 1px solid #44403C; border-radius: 6px; cursor: pointer; transition: all 0.1s; font-family: 'Inter', sans-serif; z-index: 2; }
    .copy-btn:hover { color: white; background: #44403C; }
    .copy-btn.copied { color: #4ade80; border-color: #4ade80; }

    /* ── Tokens ── */
    .token-section { margin-bottom: 32px; }
    .token-section-title { font-size: 15px; font-weight: 600; color: #1C1917; margin-bottom: 12px; padding-bottom: 8px; border-bottom: 1px solid #E7E5E4; }
    .token-grid { display: grid; gap: 6px; }
    .token-row { display: flex; align-items: center; gap: 12px; padding: 8px 12px; background: white; border: 1px solid #E7E5E4; border-radius: 8px; cursor: pointer; transition: all 0.1s; position: relative; }
    .token-row:hover { border-color: #D6D3D1; box-shadow: 0 1px 3px rgba(0,0,0,0.04); }
    .token-row.copied-row { border-color: #4ade80; background: #f0fdf4; }
    .token-swatch { width: 32px; height: 32px; border-radius: 8px; border: 1px solid rgba(0,0,0,0.06); flex-shrink: 0; }
    .token-info { flex: 1; min-width: 0; }
    .token-name { font-size: 13px; font-weight: 500; color: #1C1917; }
    .token-value { font-size: 11px; color: #78716C; font-family: 'Menlo', 'SF Mono', monospace; }
    .token-copy-hint { position: absolute; right: 12px; top: 50%; transform: translateY(-50%); font-size: 10px; color: #A8A29E; opacity: 0; transition: opacity 0.1s; white-space: nowrap; }
    .token-row:hover .token-copy-hint { opacity: 1; }
    .token-row.copied-row .token-copy-hint { opacity: 1; color: #16a34a; }

    .typo-row { display: grid; grid-template-columns: 1fr 1fr auto; align-items: center; padding: 10px 12px; background: white; border: 1px solid #E7E5E4; border-radius: 8px; cursor: pointer; transition: all 0.1s; }
    .typo-row:hover { border-color: #D6D3D1; }
    .typo-row.copied-row { border-color: #4ade80; background: #f0fdf4; }
    .typo-sample { color: #1C1917; }
    .typo-meta { font-size: 11px; color: #78716C; font-family: 'Menlo', 'SF Mono', monospace; white-space: nowrap; }
    .typo-copy-hint { font-size: 10px; color: #A8A29E; opacity: 0; transition: opacity 0.1s; text-align: right; min-width: 40px; }
    .typo-row:hover .typo-copy-hint { opacity: 1; }
    .typo-row.copied-row .typo-copy-hint { opacity: 1; color: #16a34a; }

    .radius-row { display: flex; align-items: center; gap: 12px; padding: 8px 12px; background: white; border: 1px solid #E7E5E4; border-radius: 8px; cursor: pointer; transition: all 0.1s; position: relative; }
    .radius-row:hover { border-color: #D6D3D1; }
    .radius-row.copied-row { border-color: #4ade80; background: #f0fdf4; }
    .radius-preview { width: 40px; height: 40px; background: #1c64f2; flex-shrink: 0; }
    .radius-info { flex: 1; }
    .radius-name { font-size: 13px; font-weight: 500; color: #1C1917; }
    .radius-value { font-size: 11px; color: #78716C; font-family: 'Menlo', 'SF Mono', monospace; }
    .radius-copy-hint { position: absolute; right: 12px; top: 50%; transform: translateY(-50%); font-size: 10px; color: #A8A29E; opacity: 0; transition: opacity 0.1s; }
    .radius-row:hover .radius-copy-hint { opacity: 1; }
    .radius-row.copied-row .radius-copy-hint { opacity: 1; color: #16a34a; }

    .spacing-row { display: flex; align-items: center; gap: 12px; padding: 8px 12px; background: white; border: 1px solid #E7E5E4; border-radius: 8px; cursor: pointer; transition: all 0.1s; }
    .spacing-row:hover { border-color: #D6D3D1; }
    .spacing-row.copied-row { border-color: #4ade80; background: #f0fdf4; }
    .spacing-bar { height: 20px; background: #1c64f2; border-radius: 3px; min-width: 2px; opacity: 0.7; }
    .spacing-label { font-size: 12px; font-weight: 500; color: #1C1917; min-width: 32px; }
    .spacing-px { font-size: 11px; color: #78716C; font-family: 'Menlo', 'SF Mono', monospace; }
  </style>
</head>
<body>

<!-- ── Sidebar ── -->
<div class="sidebar">
  <div class="sidebar-logo">
    <%= @sidebar_logo %>
  </div>

  <div class="nav-group" id="nav-atoms">
    <div class="nav-group-header" onclick="toggleGroup('nav-atoms')">
      <span class="nav-group-label">Atoms</span>
      <span class="nav-group-arrow">▼</span>
    </div>
    <div class="nav-group-items">
      <% @components.each do |c| %>
        <a href="#<%= c[:name] %>" class="nav-item" onclick="switchTo('components')"><%= c[:name] %></a>
      <% end %>
    </div>
  </div>

  <div class="sidebar-footer">
    <a href="/regenerate">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>
      Regenerate CSS
    </a>
  </div>
</div>

<!-- ── Main ── -->
<div class="main">

  <div class="switcher-wrapper">
    <div class="switcher">
      <button class="switcher-btn active" onclick="switchTo('components')">Components</button>
      <button class="switcher-btn" onclick="switchTo('tokens')">Style</button>
    </div>
    <div class="search-wrap">
      <svg class="search-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
      <input type="text" class="search-input" placeholder="Search…" oninput="filterComponents(this.value)">
    </div>
  </div>

  <!-- ── Components ── -->
  <div class="page-section active" id="section-components">
    <div class="section-subtitle">Atoms · <%= @components.size %> components</div>
    <% @components.each do |c| %>
      <div class="card" id="<%= c[:name] %>">
        <div class="card-header">
          <span class="card-name"><%= c[:name] %></span>
          <span class="card-file"><%= c[:filename] %></span>
        </div>
        <div class="tab-bar">
          <div class="tab active" onclick="showTab(this,'<%= c[:name] %>','stone')">Stone</div>
          <div class="tab"        onclick="showTab(this,'<%= c[:name] %>','white')">White</div>
          <div class="tab"        onclick="showTab(this,'<%= c[:name] %>','dark')">Dark</div>
          <div class="tab"        onclick="showTab(this,'<%= c[:name] %>','code')">Code</div>
        </div>
        <div id="<%= c[:name] %>-stone" class="preview-area preview-stone"><%= c[:demo_html] %></div>
        <div id="<%= c[:name] %>-white" class="preview-area preview-white" style="display:none"><%= c[:demo_html] %></div>
        <div id="<%= c[:name] %>-dark"  class="preview-area preview-dark"  style="display:none"><%= c[:demo_html] %></div>
        <div id="<%= c[:name] %>-code"  style="display:none">
          <div class="code-wrapper">
            <button class="copy-btn" onclick="copyCode(this)">Copy</button>
            <pre class="code-block"><%= c[:highlighted] %></pre>
          </div>
        </div>
      </div>
    <% end %>
    <div class="bottom-spacer"></div>
  </div>

  <!-- ── Tokens ── -->
  <div class="page-section" id="section-tokens">
    <div class="section-subtitle">Design Tokens · from CLAUDE.md</div>

    <% if @tokens[:colors]&.any? %>
    <div class="token-section">
      <div class="token-section-title">Colors</div>
      <div class="token-grid">
        <% @tokens[:colors].each do |c| %>
          <div class="token-row" onclick="copyToken(this, '<%= c[:hex] %>')" title="Click to copy">
            <div class="token-swatch" style="background:<%= c[:hex] %>"></div>
            <div class="token-info">
              <div class="token-name"><%= c[:name] %></div>
              <div class="token-value"><%= c[:hex] %><%= c[:alias] ? " · #{c[:alias]}" : '' %></div>
            </div>
            <div class="token-copy-hint">Click to copy</div>
          </div>
        <% end %>
      </div>
    </div>
    <% end %>

    <% if @tokens[:typography]&.any? %>
    <div class="token-section">
      <div class="token-section-title">Typography</div>
      <div class="token-grid">
        <% @tokens[:typography].each do |t| %>
          <% tw_class = "#{t[:class]} #{t[:weight]}" %>
          <div class="typo-row" onclick="copyToken(this, '<%= tw_class %>')" title="Click to copy Tailwind classes">
            <div class="typo-sample" style="font-size:<%= t[:size] %>; font-weight:<%= t[:weight] == 'font-bold' ? '700' : t[:weight] == 'font-semibold' ? '600' : t[:weight] == 'font-medium' ? '500' : '400' %>">
              The quick brown fox<%= t[:note] ? " — #{t[:note]}" : '' %>
            </div>
            <div class="typo-meta"><%= t[:class] %> / <%= t[:weight] %></div>
            <div class="typo-copy-hint">Copy</div>
          </div>
        <% end %>
      </div>
    </div>
    <% end %>

    <% if @tokens[:radii]&.any? %>
    <div class="token-section">
      <div class="token-section-title">Border Radius</div>
      <div class="token-grid">
        <% @tokens[:radii].each do |r| %>
          <div class="radius-row" onclick="copyToken(this, '<%= r[:class] %>')" title="Click to copy">
            <div class="radius-preview" style="border-radius:<%= r[:size] %>"></div>
            <div class="radius-info">
              <div class="radius-name"><%= r[:class] %></div>
              <div class="radius-value"><%= r[:size] %></div>
            </div>
            <div class="radius-copy-hint">Copy</div>
          </div>
        <% end %>
      </div>
    </div>
    <% end %>

    <% if @tokens[:spacing]&.any? %>
    <div class="token-section">
      <div class="token-section-title">Spacing Scale</div>
      <div class="token-grid">
        <% @tokens[:spacing].each do |s| %>
          <div class="spacing-row" onclick="copyToken(this, '<%= s %>px')" title="Click to copy">
            <div class="spacing-label"><%= s %></div>
            <div class="spacing-bar" style="width:<%= s.to_i * 4 %>px"></div>
            <div class="spacing-px"><%= s %>px</div>
          </div>
        <% end %>
      </div>
    </div>
    <% end %>

    <% if @tokens[:shadows]&.any? %>
    <div class="token-section">
      <div class="token-section-title">Shadows</div>
      <div class="token-grid">
        <% @tokens[:shadows].each do |s| %>
          <div class="token-row" onclick="copyToken(this, '<%= s[:value] %>')" title="Click to copy">
            <div class="token-swatch" style="background:white;box-shadow:<%= s[:value] %>;border:none"></div>
            <div class="token-info">
              <div class="token-name"><%= s[:name] %></div>
              <div class="token-value"><%= s[:value] %></div>
            </div>
            <div class="token-copy-hint">Copy</div>
          </div>
        <% end %>
      </div>
    </div>
    <% end %>
  </div>

</div>

<script>
  function showTab(btn, name, tab) {
    btn.closest('.card').querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    btn.classList.add('active');
    ['stone','white','dark','code'].forEach(t => {
      const el = document.getElementById(name + '-' + t);
      if (el) el.style.display = 'none';
    });
    document.getElementById(name + '-' + tab).style.display = 'block';
  }

  function switchTo(page) {
    document.querySelectorAll('.switcher-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.page-section').forEach(s => s.classList.remove('active'));
    if (page === 'tokens') {
      document.querySelectorAll('.switcher-btn')[1].classList.add('active');
      document.getElementById('section-tokens').classList.add('active');
    } else {
      document.querySelectorAll('.switcher-btn')[0].classList.add('active');
      document.getElementById('section-components').classList.add('active');
    }
  }

  function toggleGroup(id) {
    document.getElementById(id).classList.toggle('collapsed');
  }

  function copyToClipboard(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text);
    }
    // Fallback for non-HTTPS / file://
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); } catch(e) {}
    document.body.removeChild(ta);
    return Promise.resolve();
  }

  function copyCode(btn) {
    const code = btn.parentElement.querySelector('.code-block').textContent;
    copyToClipboard(code).then(() => {
      btn.textContent = 'Copied!';
      btn.classList.add('copied');
      setTimeout(() => { btn.textContent = 'Copy'; btn.classList.remove('copied'); }, 1500);
    });
  }

  function copyToken(row, value) {
    copyToClipboard(value).then(() => {
      row.classList.add('copied-row');
      const hint = row.querySelector('[class*="copy-hint"]');
      if (hint) {
        const old = hint.textContent;
        hint.textContent = 'Copied!';
        setTimeout(() => { hint.textContent = old; row.classList.remove('copied-row'); }, 1200);
      } else {
        setTimeout(() => row.classList.remove('copied-row'), 1200);
      }
    });
  }

  function filterComponents(query) {
    const q = query.toLowerCase().trim();
    document.querySelectorAll('#section-components .card').forEach(card => {
      const name = card.querySelector('.card-name')?.textContent.toLowerCase() || '';
      card.style.display = (!q || name.includes(q)) ? '' : 'none';
    });
    document.querySelectorAll('.nav-group-items .nav-item').forEach(item => {
      const name = item.textContent.toLowerCase();
      item.style.display = (!q || name.includes(q)) ? '' : 'none';
    });
    document.querySelectorAll('#section-tokens .token-row, #section-tokens .typo-row, #section-tokens .radius-row, #section-tokens .spacing-row').forEach(row => {
      const text = row.textContent.toLowerCase();
      row.style.display = (!q || text.includes(q)) ? '' : 'none';
    });
  }

  // Nav click: smooth scroll with offset
  document.querySelectorAll('.nav-item[href^="#"]').forEach(link => {
    link.addEventListener('click', (e) => {
      e.preventDefault();
      const id = link.getAttribute('href').slice(1);
      const el = document.getElementById(id);
      if (el) {
        const y = el.getBoundingClientRect().top + window.scrollY - 20;
        window.scrollTo({ top: y, behavior: 'smooth' });
      }
    });
  });

  window.addEventListener('scroll', () => {
    document.querySelectorAll('.card[id]').forEach(card => {
      const rect = card.getBoundingClientRect();
      if (rect.top <= 100 && rect.bottom > 100) {
        document.querySelectorAll('.nav-item').forEach(x => x.classList.remove('active'));
        const nav = document.querySelector('.nav-item[href="#' + card.id + '"]');
        if (nav) nav.classList.add('active');
      }
    });
  });
</script>

</body>
</html>
