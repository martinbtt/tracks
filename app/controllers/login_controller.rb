class LoginController < ApplicationController
  
  layout 'login'
  filter_parameter_logging :user_password 
  skip_before_filter :set_session_expiration
  skip_before_filter :login_required
  before_filter :login_optional
  before_filter :get_current_user
  open_id_consumer if openid_enabled?
  
  def login
    @page_title = "TRACKS::Login"
    @openid_url = cookies[:openid_url] if openid_enabled?
    case request.method
      when :post
        if @user = User.authenticate(params['user_login'], params['user_password'])
          session['user_id'] = @user.id
          # If checkbox on login page checked, we don't expire the session after 1 hour
          # of inactivity and we remember this user for future browser sessions
          session['noexpiry'] = params['user_noexpiry']
          msg = (should_expire_sessions?) ? "will expire after 1 hour of inactivity." : "will not expire." 
          notify :notice, "Login successful: session #{msg}"
          cookies[:tracks_login] = { :value => @user.login, :expires => Time.now + 1.year, :secure => TRACKS_COOKIES_SECURE }
          unless should_expire_sessions?
            @user.remember_me
            cookies[:auth_token] = { :value => @user.remember_token , :expires => @user.remember_token_expires_at, :secure => TRACKS_COOKIES_SECURE }
          end
          redirect_back_or_home
          return
        else
          @login = params['user_login']
          notify :warning, "Login unsuccessful"
        end
      when :get
        if User.no_users_yet?
          redirect_to :controller => 'users', :action => 'new'
          return
        end
    end
    respond_to do |format|
      format.html
      format.m   { render :action => 'login_mobile.html.erb', :layout => 'mobile' }
    end
  end
  
  def begin
    # If the URL was unusable (either because of network conditions,
    # a server error, or that the response returned was not an OpenID
    # identity page), the library will return HTTP_FAILURE or PARSE_ERROR.
    # Let the user know that the URL is unusable.
    case open_id_response.status
      when OpenID::SUCCESS
        session['openid_url'] = params[:openid_url]
        session['user_noexpiry'] = params[:user_noexpiry]
        # The URL was a valid identity URL. Now we just need to send a redirect
        # to the server using the redirect_url the library created for us.

        # redirect to the server
        respond_to do |format|
          format.html { redirect_to open_id_response.redirect_url((request.protocol + request.host_with_port + "/"), open_id_complete_url) }
          format.m { redirect_to open_id_response.redirect_url((request.protocol + request.host_with_port + "/"), formatted_open_id_complete_url(:format => 'm')) }
        end
      else
        notify :warning, "Unable to find openid server for <q>#{openid_url}</q>"
        redirect_to_login
    end
  end

  def complete
    openid_url = session['openid_url']
    if openid_url.blank?
      notify :error, "expected an openid_url"
    end
      
    case open_id_response.status
      when OpenID::FAILURE
        # In the case of failure, if info is non-nil, it is the
        # URL that we were verifying. We include it in the error
        # message to help the user figure out what happened.
        if open_id_response.identity_url
          msg = "Verification of #{openid_url}(#{open_id_response.identity_url}) failed. "
        else
          msg = "Verification failed. "
        end
        notify :error, open_id_response.msg.to_s + msg

      when OpenID::SUCCESS
        # Success means that the transaction completed without
        # error. If info is nil, it means that the user cancelled
        # the verification.
        @user = User.find_by_open_id_url(openid_url)
        unless (@user.nil?)
          session['user_id'] = @user.id
          session['noexpiry'] = session['user_noexpiry']
          msg = (should_expire_sessions?) ? "will expire after 1 hour of inactivity." : "will not expire." 
          notify :notice, "You have successfully verified #{openid_url} as your identity. Login successful: session #{msg}"
          cookies[:tracks_login] = { :value => @user.login, :expires => Time.now + 1.year, :secure => TRACKS_COOKIES_SECURE }
          unless should_expire_sessions?
            @user.remember_me
            cookies[:auth_token] = { :value => @user.remember_token , :expires => @user.remember_token_expires_at, :secure => TRACKS_COOKIES_SECURE }
          end
          cookies[:openid_url] = { :value => openid_url, :expires => Time.now + 1.year, :secure => TRACKS_COOKIES_SECURE }
          redirect_back_or_home
        else
          notify :warning, "You have successfully verified #{openid_url} as your identity, but you do not have a Tracks account. Please ask your administrator to sign you up."
        end

      when OpenID::CANCEL
        notify :warning, "Verification cancelled."

      else
        notify :warning, "Unknown response status: #{open_id_response.status}"
    end
    redirect_to_login unless performed?
  end

  def logout
    @user.forget_me if logged_in?
    cookies.delete :auth_token
    session['user_id'] = nil
    reset_session
    notify :notice, "You have been logged out of Tracks."
    redirect_to_login
  end
  
  def check_expiry
    # Gets called by periodically_call_remote to check whether 
    # the session has timed out yet
    unless session == nil
      if session
        return unless should_expire_sessions?
        # Get expiry time (allow ten seconds window for the case where we have none)
        expiry_time = session['expiry_time'] || Time.now + 10
        @time_left = expiry_time - Time.now
        if @time_left < (10*60) # Session will time out before the next check
          @msg = "Session has timed out. Please "
        else
          @msg = ""
        end
      end
    end
    respond_to do |format|
      format.js
    end
  end
  
  private
      
  def redirect_to_login
    respond_to do |format|
      format.html { redirect_to login_path }
      format.m { redirect_to formatted_login_path(:format => 'm') }
    end
  end
  
  def should_expire_sessions?
    session['noexpiry'] != "on"
  end
    
end
