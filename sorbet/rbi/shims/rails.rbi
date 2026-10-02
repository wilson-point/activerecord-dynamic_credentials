# typed: strict

# Rails is optional at runtime. This shim exists so the Railtie and the
# `defined?(Rails)` branches can be checked without a railties dependency.
module Rails
  class << self
    sig { returns(T.nilable(Application)) }
    def application; end

    sig { returns(T.untyped) }
    def logger; end
  end

  class Application
    sig { returns(T.untyped) }
    def config; end
  end

  class Railtie
    sig { params(name: String, opts: T::Hash[Symbol, T.untyped], blk: T.nilable(T.proc.void)).void }
    def self.initializer(name, opts = {}, &blk); end
  end
end
