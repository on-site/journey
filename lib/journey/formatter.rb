module Journey
  ###
  # The Formatter class is used for formatting URLs.  For example, parameters
  # passed to +url_for+ in rails will eventually call Formatter#generate
  class Formatter
    attr_reader :routes

    def initialize routes, cache
      @routes = routes
      @cache  = cache
    end

    def generate key, name, options, recall = {}, parameterize = nil
      constraints = recall.merge options

      match_route(name, constraints) do |route|
        data = constraints.dup

        keys_to_keep = route.parts.reverse.drop_while { |part|
          !options.key?(part) || (options[part] || recall[part]).nil?
        } | route.required_parts

        (data.keys - keys_to_keep).each do |bad_key|
          data.delete bad_key
        end

        parameterized_parts = data.dup

        if parameterize
          parameterized_parts.each do |k,v|
            parameterized_parts[k] = parameterize[:parameterize].call(k, v)
          end
        end

        parameterized_parts.keep_if { |_,v| v  }

        next unless verify_required_parts!(route, parameterized_parts)

        z = Hash[options.to_a - data.to_a - route.defaults.to_a]

        return [route.format(parameterized_parts), z]
      end

      raise Router::RoutingError
    end

    private
    def named_routes
      routes.named_routes
    end

    def match_route name, options
      if named_routes.key? name
        yield named_routes[name]
      else
        #routes = possibles(@cache, options.to_a)
        routes = non_recursive(cache, options.to_a)

        hash = routes.group_by { |_, r|
          r.score options
        }

        hash.keys.sort.reverse_each do |score|
          next if score < 0

          hash[score].sort_by { |i,_| i }.each do |_,route|
            yield route
          end
        end
      end
    end

    def non_recursive cache, options
      routes = []
      stack  = [cache]

      while stack.any?
        c = stack.shift
        routes.concat c[:___routes] if c.key? :___routes

        options.each do |pair|
          stack << c[pair] if c.key? pair
        end
      end

      routes
    end

    def possibles cache, options, depth = 0
      cache.fetch(:___routes) { [] } + options.find_all { |pair|
        cache.key? pair
      }.map { |pair|
        possibles(cache[pair], options, depth + 1)
      }.flatten(1)
    end

    def verify_required_parts! route, parts
      tests = route.path.requirements
      route.required_parts.all? { |key|
        if tests.key? key
          /\A#{tests[key]}\Z/ === parts[key]
        else
          true
        end
      }
    end

    def cache
      @cache
    end
  end
end
