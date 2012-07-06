module DeviseCasAuthenticatable
  module SingleSignOut

    def self.rails3?
      defined?(::Rails) && ::Rails::VERSION::MAJOR == 3
    end

    module StoreSessionIdFilter
      extend ActiveSupport::Concern

      included do
        before_filter :store_session_id_for_cas_ticket
      end

      def store_session_id_for_cas_ticket
        if session['cas_last_valid_ticket_store']
          sid = env['rack.session.options'][:id]
          Rails.logger.info "Storing sid #{sid} for ticket #{session['cas_last_valid_ticket']}"
          ::DeviseCasAuthenticatable::SingleSignOut::Strategies.current_strategy.store_session_id_for_index(session['cas_last_valid_ticket'], sid)
          session['cas_last_valid_ticket_store'] = false
        end
      end
    end

    # Supports destroying sessions by ID for ActiveRecord and Redis session stores
    module DestroySession
      def session_store_class
        @session_store_class ||=
          begin
            if ::DeviseCasAuthenticatable::SingleSignOut.rails3?
              # => Rails 3
              ::Rails.application.config.session_store
            else
              # => Rails 2
              ActionController::Base.session_store
            end
          rescue NameError => e
            # for older versions of Rails (prior to 2.3)
            ActionController::Base.session_options[:database_manager]
          end
      end

      def current_session_store
        app = Rails.application
        begin
          app = app.instance_variable_get :@app
        end until app.nil? or app.class == session_store_class
        app
      end

      def destroy_session_by_id(sid)
        if session_store_class.name == "ActionDispatch::Session::DalliStore"
          @pool ||= begin
            if Rails.application.config.session_options[:cache]
              Rails.application.config.session_options[:cache]
            else
              opts = {:namespace => 'rack:session'}.merge(Rails.application.config.session_options)
              ::Dalli::Client.new opts[:memcache_server], opts
            end
          end
          @pool.delete(sid)
        if session_store_class.name == "ActionDispatch::Session::RedisStore"
          @pool ||= begin
            redis_server = ::Rails.application.config.session_options[:redis_server]
            redis_server ||= ::Rails.application.config.session_options[:servers]
            redis_server ||= "redis://127.0.0.1:6379/0/rack:session"
            ::Redis::Factory.create redis_server
          end
          @pool.del(sid)
        elsif session_store_class == ActiveRecord::SessionStore
          session = current_session_store::Session.find_by_session_id(sid)
          session.destroy if session
          true
        elsif session_store_class.name =~ /RedisSessionStore/
          current_session_store.instance_variable_get(:@pool).del(sid)
          true
        else
          logger.error "Cannot process logout request because this Rails application's session store is "+
                " #{current_session_store.name.inspect} and is not a support session store type for Single Sign-Out."
          false
        end
      end
    end

  end
end

require 'devise_cas_authenticatable/single_sign_out/strategies'
require 'devise_cas_authenticatable/single_sign_out/strategies/base'
require 'devise_cas_authenticatable/single_sign_out/strategies/rails_cache'
