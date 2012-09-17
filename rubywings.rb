# -*- coding: utf-8 -*-

%w(rubygems oauth twitter weibo_2 omniauth).each { |d| require d }
%w(omniauth-openid openid/store/filesystem).each { |d| require d }
%w(redis sinatra haml sass).each { |d| require d }

# Use session in Sinatra, don't forget to set secret key in config.ru.
enable :sessions

APP_NAME = 'Ruby Wings'
APP_VERSION = '0.3'
BASE_URL = 'http://imwilsonxu.net/rubywings'
#BASE_URL = 'http://127.0.0.1/rubywings'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

# Weibo oauth conf
WEIBO_CALLBACK_URL = "#{BASE_URL}/weibo_callback"
WeiboOAuth2::Config.api_key = ENV['WEIBO_API_KEY']
WeiboOAuth2::Config.api_secret = ENV['WEIBO_API_SECRET']
WeiboOAuth2::Config.redirect_uri = WEIBO_CALLBACK_URL

# Twitter oauth conf
TWITTER_CALLBACK_URL = "#{BASE_URL}/twitter_callback"
$TWITTER_CONSUMER = OAuth::Consumer.new(
    ENV['TWITTER_CONSUMER_KEY'],
    ENV['TWITTER_CONSUMER_SECRET'], 
    :site => 'http://api.twitter.com')
# Global conf
Twitter.configure do |config|
    config.consumer_key = ENV['TWITTER_CONSUMER_KEY']
    config.consumer_secret = ENV['TWITTER_CONSUMER_SECRET']
end

# Redis
$r = Redis.new(:host => '127.0.0.1', :port => '100001')

# Logger
use Rack::Logger
$logger = Logger.new('logs/rubywings.log')
$logger.level = Logger::INFO

# Openid
use Rack::Session::Cookie
use OmniAuth::Builder do
    provider :open_id, :store => OpenID::Store::Filesystem.new('/tmp')
end

##############################################################################

before do
    if session[:user_id]
        $user = $r.hgetall("user:#{session[:user_id]}")

        weibo = $r.hgetall("user.weibo.auth:#{$user['id']}")
        if weibo 
            session[:weibo_uid] = weibo['user_id']
            session[:weibo_access_token] = weibo['access_token']
            session[:weibo_expires_at] = weibo['expires_at']
        end

        twitter = $r.hgetall("user.twitter.auth:#{$user['id']}")
        if twitter
            session[:twitter_uid] = twitter['user_id']
            session[:twitter_oauth_token] = twitter['oauth_token']
            session[:twitter_oauth_token_secret] = twitter['oauth_token_secret']
        end
    else
        $user = nil
    end
    $logger.debug("#{$user} - #{session[:weibo_uid]} - #{session[:twitter_uid]}")
end

[:get, :post].each do |method|
    send method, '/auth/:provider/callback' do
        #$logger.debug(request.env['omniauth.auth'].info)
        #request.env['omniauth.auth'].info.to_hash.inspect

        data = request.env['omniauth.auth'].info
        user_id = $r.get("email.to.id:#{data['email']}")
        if user_id
            $user = $r.hgetall("user:#{user_id}")
        else
            # Create a new user.
            id = $r.incr("users.count")
            $r.hmset("user:#{id}",
                "id", id,
                "email", data['email'],
                "name", data['name'],
                "nickname", data['nickname'],
                "password", "",
                "ctime", Time.now.to_i)
            $r.set("email.to.id:#{data['email']}", id)
            $r.zadd("users.cron", Time.now.to_i, id)

            $user = $r.hgetall("user:#{id}")
        end

        session['user_id'] = $user['id']
        weibo = $r.hgetall("user.weibo.auth:#{$user['id']}")
        if weibo 
            session[:weibo_uid] = weibo['user_id']
            session[:weibo_access_token] = weibo['access_token']
            session[:weibo_expires_at] = weibo['expires_at']
        end
        twitter = $r.hgetall("user.twitter.auth:#{$user['id']}")
        if twitter
            session[:twitter_uid] = twitter['user_id']
            session[:twitter_oauth_token] = twitter['oauth_token']
            session[:twitter_oauth_token_secret] = twitter['oauth_token_secret']
        end

        redirect BASE_URL
    end
end

#error OpenIDAuthError do
#    "Oops, could u pls use yourid.myopenid.com? We're struggling with other openid provider :("
#end
#
#[:get, :post].each do |method|
#    send method, '/auth/failure' do
#        raise OpenIDAuthError, ''
#    end
#end

get '/' do
    redirect '/rubywings/auth/open_id' if !$user
    haml :index
end

get '/weibo' do
    redirect '/rubywings/auth/open_id' if !$user

    weibo_client = get_weibo_client
    redirect weibo_client.authorize_url
end

get '/weibo_callback' do
    redirect '/rubywings/auth/open_id' if !$user

    weibo_client = get_weibo_client
    weibo_access_token = weibo_client.auth_code.get_token(params[:code].to_s)
    session[:weibo_uid] = weibo_access_token.params["uid"]
    session[:weibo_access_token] = weibo_access_token.token
    session[:weibo_expires_at] = weibo_access_token.expires_at
    $r.hmset("user.weibo.auth:#{$user['id']}",
             "user_id", session[:weibo_uid],
             "access_token", session[:weibo_access_token],
             "expires_at", session[:weibo_expires_at])
    $logger.debug("Weibo token: #{session[:weibo_access_token]}")
    
    redirect BASE_URL
end

get '/twitter' do
    redirect '/rubywings/auth/open_id' if !$user
    
    # Start the process by requesting a token
    twitter_request_token = $TWITTER_CONSUMER.get_request_token(:oauth_callback => TWITTER_CALLBACK_URL)
    # Not authorized yet, store this request token in session.
    # Retrieving it after Twitter oauth service popluated it. 
    session[:twitter_request_token] = twitter_request_token
    
    redirect twitter_request_token.authorize_url(:oauth_callback => TWITTER_CALLBACK_URL)
end

get '/twitter_callback' do
    redirect '/rubywings/auth/open_id' if !$user
    
    # When user returns create an access_token
    twitter_access_token = session[:twitter_request_token].get_access_token
    session[:twitter_oauth_token] = twitter_access_token.token
    session[:twitter_oauth_token_secret] = twitter_access_token.secret
    twitter_client = get_twitter_client
    session[:twitter_uid] = twitter_client.user.id

    $r.hmset("user.twitter.auth:#{$user['id']}",
             "user_id", session[:twitter_uid],
             "oauth_token", session[:twitter_oauth_token],
             "oauth_token_secret", session[:twitter_oauth_token_secret])

    redirect BASE_URL
end

get '/signout_weibo' do
    reset_weibo_session
    redirect BASE_URL
end 

get '/signout_twitter' do
    reset_twitter_session
    redirect BASE_URL
end 

get '/signout' do
    reset_session
    redirect BASE_URL
end 

get '/screen.css' do
    content_type 'text/css'
    sass :screen
end

post '/update' do
    redirect '/rubywings/auth/open_id' if !$user
    
    $logger.info('Update weibo and tweet...')

    # Parse tags
    tags_arr = params[:tags].split(/,+\s+|\s+|,+/)

    if session[:twitter_oauth_token]
        twitter_client = get_twitter_client

        twitter_tags = tags_arr.map {|tag| "##{tag}"}.join(" ")
        unless params[:file] && (tmpfile = params[:file][:tempfile]) && (name = params[:file][:filename])
            text = [params[:status], twitter_tags].join(" ")
            twitter_client.update(text)
            $logger.info("Tweet(#{text}) updated!")
        else
            File.open(tmpfile.path) do |media|
                text = [params[:status], twitter_tags].join(" ")
                twitter_client.update_with_media(text, media)
                $logger.info("Tweet(#{text}) with photo updated!")
            end
        end
    end

    if session[:weibo_access_token]
        weibo_client = get_weibo_client
        statuses = weibo_client.statuses

        weibo_tags = tags_arr.map {|tag| "##{tag}#"}.join(" ")
        unless params[:file] && (tmpfile = params[:file][:tempfile]) && (name = params[:file][:filename])
            text = [params[:status], weibo_tags].join(" ")
            statuses.update(text)
            $logger.info("Weibo(#{text}) updated!")
        else
            File.open(tmpfile.path) do |media|
                text = [params[:status], weibo_tags].join(" ")
                statuses.upload(text, media)
                $logger.info("Weibo(#{text}) with photo updated!")
            end
        end
    end

    redirect BASE_URL
end

helpers do 
    def reset_weibo_session
        session[:weibo_uid] = nil
        session[:weibo_access_token] = nil
        session[:weibo_expires_at] = nil
    end

    def reset_twitter_session
        session[:twitter_uid] = nil
        session[:twitter_oauth_token] = nil
        session[:twitter_oauth_token_secret] = nil
    end

    def reset_session
        reset_weibo_session
        reset_twitter_session
        session[:user_id] = nil
    end

    def get_weibo_client
        weibo_client = WeiboOAuth2::Client.new
        if session[:weibo_access_token] && !weibo_client.authorized?
            weibo_hash = {
                :access_token => session[:weibo_access_token], 
                :expires_at => session[:weibo_expires_at]
            }
            weibo_client.get_token_from_hash(weibo_hash) 
        end
        weibo_client 
    end

    def get_twitter_client
        Twitter::Client.new(
            :oauth_token => session[:twitter_oauth_token],
            :oauth_token_secret => session[:twitter_oauth_token_secret],
        )
    end

end

__END__

# Just showing off inline template in Sinatra :)

@@ layout
%html
    %head
        %meta(content='text/html;charset=UTF-8' http-equiv='content-type')
        %title="Ruby Wings - Bring your words to Twitter, Weibo and more"
        %link{:href => "/rubywings/screen.css", :rel =>"stylesheet", :type => "text/css", :media => "screen"}
    %body
        = yield
