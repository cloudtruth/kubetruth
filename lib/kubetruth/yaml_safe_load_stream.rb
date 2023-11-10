require 'yaml'
module YAML
  # copied from YAML.safe_load and mutabled to use parse_stream with a block
  def self.safe_load_stream(yaml, permitted_classes: [], permitted_symbols: [], aliases: false, filename: nil, fallback: nil, symbolize_names: false, freeze: false, strict_integer: false)
    yamls = []
    parse_stream(yaml, filename: filename) do |result|
      return fallback unless result

      class_loader = ClassLoader::Restricted.new(permitted_classes.map(&:to_s),
                                                 permitted_symbols.map(&:to_s))
      scanner      = ScalarScanner.new class_loader, strict_integer: strict_integer
      visitor = if aliases
        Visitors::ToRuby.new scanner, class_loader, symbolize_names: symbolize_names, freeze: freeze
      else
        Visitors::NoAliasRuby.new scanner, class_loader, symbolize_names: symbolize_names, freeze: freeze
      end
      result = visitor.accept result
      yield result if block_given?
      yamls << result
    end
    yamls
  end
end
