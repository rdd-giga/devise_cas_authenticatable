class Devise::CasSessionsController < Devise::SessionsController  
  include DeviseCasAuthenticatable::SingleSignOut::DestroySession
  unloadable

  skip_before_filter :verify_authenticity_token, :only => [:single_sign_out]

  def new
    unless returning_from_cas?
      redirect_to(cas_login_url)
    end
  end
  
  def service
    warden.authenticate!(:scope => resource_name)
    redirect_to after_sign_in_path_for(resource_name)
  end
  
  def unregistered
  end
  
  def destroy
    # if :cas_create_user is false a CAS session might be open but not signed_in
    # in such case we destroy the session here
    if signed_in?(resource_name)
      sign_out(resource_name)
    else
      reset_session
    end

    if ::Devise.cas_logout_url_param == 'destination'
      if !::Devise.cas_destination_url.blank?
        destination_url = Devise.cas_destination_url
      else
        destination_url = request.protocol
        destination_url << request.host
        destination_url << ":#{request.port.to_s}" unless request.port == 80
        destination_url << after_sign_out_path_for(resource_name)
      end
    end
    
    if ::Devise.cas_logout_url_param == 'follow'
      if !::Devise.cas_follow_url.blank?
        follow_url = Devise.cas_follow_url
      else
        follow_url = request.protocol
        follow_url << request.host
        follow_url << ":#{request.port.to_s}" unless request.port == 80
        follow_url << after_sign_out_path_for(resource_name)
      end
    end
    
    redirect_to(::Devise.cas_client.logout_url(destination_url, follow_url))
  end

  def single_sign_out
    if ::Devise.cas_enable_single_sign_out
      session_index = read_session_index
      if session_index
        logger.debug "Intercepted single-sign-out request for CAS session #{session_index}."
        session_id = ::DeviseCasAuthenticatable::SingleSignOut::Strategies.current_strategy.find_session_id_by_index(session_index)
        if session_id
          destroy_cas_session(session_id, session_index)
        end
      else
        logger.warn "Ignoring CAS single-sign-out request as no session index could be parsed from the parameters."
      end
    else
      logger.warn "Ignoring CAS single-sign-out request as feature is not currently enabled."
    end

    render :nothing => true
  end

  private

  def read_session_index
    if request.headers['CONTENT_TYPE'] =~ %r{^multipart/}
      false
    elsif request.post? && params['logoutRequest'] =~
        %r{^<samlp:LogoutRequest.*?<samlp:SessionIndex>(.*)</samlp:SessionIndex>}m
      $~[1]
    else
      false
    end
  end

  def destroy_cas_session(session_id, session_index)
    logger.debug "Destroying cas session #{session_id} for ticket #{session_index}"
    if destroy_session_by_id(session_id)
      logger.debug "Destroyed session #{session_id} corresponding to service ticket #{session_index}."
    end

    ::DeviseCasAuthenticatable::SingleSignOut::Strategies.current_strategy.delete_session_index(session_index)
  end

  def returning_from_cas?
    params[:ticket] || request.referer =~ /^#{::Devise.cas_client.cas_base_url}/
  end
  
  def cas_login_url
    ::Devise.cas_client.add_service_to_login_url(::Devise.cas_service_url(request.url, devise_mapping))
  end
  helper_method :cas_login_url
end
