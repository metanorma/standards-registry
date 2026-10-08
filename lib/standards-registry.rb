# frozen_string_literal: true

require_relative "registry"
begin
  require "jekyll"
rescue LoadError
  # Renderer only loads under Jekyll; the engine core stays framework-free.
else
  require_relative "standards-registry/renderer"
end

