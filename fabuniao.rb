# -*- coding: utf-8 -*-

%w(rubygems oauth twitter weibo_2 time-ago-in-words sinatra haml sass).each { |dependency| require dependency }

enable :sessions

WeiboOAuth2::Config.api_key = ENV['FABUNIAO_API_KEY']
WeiboOAuth2::Config.api_secret = ENV['FABUNIAO_API_SECRET']
WeiboOAuth2::Config.redirect_uri = ENV['FABUNIAO_REDIRECT_URI']

$twitter_callback_url = "http://127.0.0.1/twitter_callback"
$consumer = OAuth::Consumer.new(
    ENV['TWITTER_CONSUMER_KEY'],
    ENV['TWITTER_CONSUMER_SECRET'], 
    :site => 'http://api.twitter.com')

Twitter.configure do |config|
    config.consumer_key = ENV['TWITTER_CONSUMER_KEY']
    config.consumer_secret = ENV['TWITTER_CONSUMER_SECRET']
end

# Logger
use Rack::Logger
$logger = Logger.new('logs/fabuniao.log')
$logger.level = Logger::DEBUG

before do
    $logger.debug(session)
    $logger.debug(session[:twitter_oauth_token])
    $logger.debug(session[:twitter_oauth_token_secret])
    $logger.debug(is_twitter_auth)
end

get '/' do
    @weibo_user = get_weibo_client.users.show_by_uid(session[:weibo_uid]) if is_weibo_auth
    @twitter_user = get_twitter_client.user if session[:twitter_oauth_token] if is_twitter_auth

    haml :index
end

get '/weibo' do
    weibo_client = get_weibo_client
    redirect weibo_client.authorize_url
end

get '/weibo_callback' do
    weibo_client = get_weibo_client
    weibo_access_token = weibo_client.auth_code.get_token(params[:code].to_s)
    session[:weibo_uid] = weibo_access_token.params["uid"]
    session[:weibo_access_token] = weibo_access_token.token
    session[:weibo_expires_at] = weibo_access_token.expires_at
    #@weibo_user = weibo_client.users.show_by_uid(session[:weibo_uid].to_i)
    
    redirect '/'
end

get '/twitter' do
    twitter_request_token = $consumer.get_request_token(:oauth_callback => "http://127.0.0.1/twitter_callback")
    session[:twitter_request_token] = twitter_request_token
    redirect twitter_request_token.authorize_url(:oauth_callback => "http://127.0.0.1/twitter_callback")
end

get '/twitter_callback' do
    twitter_access_token = session[:twitter_request_token].get_access_token
    session[:twitter_oauth_token] = twitter_access_token.token
    session[:twitter_oauth_token_secret] = twitter_access_token.secret

    twitter_client = get_twitter_client
    session[:twitter_uid] = twitter_client.user.id

    redirect '/'
end

get '/logout_weibo' do
    reset_weibo_session
    redirect '/'
end 

get '/logout_twitter' do
    reset_twitter_session
    redirect '/'
end 

get '/logout' do
    reset_session
    redirect '/'
end 

get '/screen.css' do
    content_type 'text/css'
    sass :screen
end

post '/update' do

    $logger.debug('Update weibo and tweet...')

    weibo_client = WeiboOAuth2::Client.new
    weibo_client.get_token_from_hash({:access_token => session[:weibo_access_token], :expires_at => session[:weibo_expires_at]}) 
    statuses = weibo_client.statuses

    twitter_client = get_twitter_client

    tags_arr = params[:tags].split(/,+\s+|\s+|,+/)
    weibo_tags = tags_arr.map {|tag| "##{tag}#"}.join(" ")
    twitter_tags = tags_arr.map {|tag| "##{tag}"}.join(" ")

    unless params[:file] && (tmpfile = params[:file][:tempfile]) && (name = params[:file][:filename])
        $logger.debug([params[:status], weibo_tags].join(" "))
        #statuses.update([params[:status], weibo_tags].join(" "))
        $logger.debug('Weibo updated!')

        $logger.debug(([params[:status], twitter_tags].join(" ")))
        #twitter_client.update(([params[:status], twitter_tags].join(" ")))
        $logger.debug('Tweet updated!')
    else
        File.open(tmpfile.path) do |media|
            statuses.upload(params[:status] || '', media)
            $logger.debug('Weibo with photo updated!')

            twitter_client.update_with_media(params[:status] || '', media)
            $logger.debug('Tweet with photo updated!')
        end
    end

    redirect '/'
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
    end

    def get_weibo_client
        WeiboOAuth2::Client.new
    end

    def get_twitter_client
        return nil if is_twitter_auth

        Twitter::Client.new(
            :oauth_token => session[:twitter_oauth_token],
            :oauth_token_secret => session[:twitter_oauth_token_secret],
        )
    end

    def is_weibo_auth
        return session[:weibo_access_token]
    end

    def is_twitter_auth
        return session[:twitter_oauth_token]
    end
end
