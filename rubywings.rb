# -*- coding: utf-8 -*-

%w(rubygems oauth twitter weibo_2 sinatra haml sass).each { |d| require d }

# Use session in Sinatra, don't forget to set secret key in config.ru.
enable :sessions

APP_NAME = 'Ruby Wings'
APP_VERSION = '0.2'
BASE_URL = 'http://127.0.0.1'

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

# Logger
use Rack::Logger
$logger = Logger.new('logs/debug.log')
$logger.level = Logger::DEBUG

##############################################################################

get '/' do
    #@weibo_user = get_weibo_client.users.show_by_uid(session[:weibo_uid]) if session[:weibo_access_token]
    #@twitter_user = get_twitter_client.user if session[:twitter_oauth_token]
    
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
    $logger.debug("Weibo token: #{session[:weibo_access_token]}")
    
    redirect '/'
end

get '/twitter' do
    # Start the process by requesting a token
    twitter_request_token = $TWITTER_CONSUMER.get_request_token(:oauth_callback => TWITTER_CALLBACK_URL)
    # Not authorized yet, store this request token in session.
    # Retrieving it after Twitter oauth service popluated it. 
    session[:twitter_request_token] = twitter_request_token
    redirect twitter_request_token.authorize_url(:oauth_callback => TWITTER_CALLBACK_URL)
end

get '/twitter_callback' do
    # When user returns create an access_token
    twitter_access_token = session[:twitter_request_token].get_access_token
    session[:twitter_oauth_token] = twitter_access_token.token
    session[:twitter_oauth_token_secret] = twitter_access_token.secret
    $logger.debug("Twitter token: #{session[:twitter_oauth_token]}")
    $logger.debug("Twitter secret: #{session[:twitter_oauth_token_secret]}")

    twitter_client = get_twitter_client
    if !twitter_client
        $logger.debug("Twitter client is nil, fuck!")
    else
        session[:twitter_uid] = twitter_client.user.id
    end

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
