# -*- coding: utf-8 -*-

require 'rubygems'
require 'oauth'
require 'twitter'
require 'weibo_2'
require 'time-ago-in-words'

%w(sinatra haml sass).each { |dependency| require dependency }
enable :sessions

WeiboOAuth2::Config.api_key = ENV['FABUNIAO_API_KEY']
WeiboOAuth2::Config.api_secret = ENV['FABUNIAO_API_SECRET']
WeiboOAuth2::Config.redirect_uri = ENV['FABUNIAO_REDIRECT_URI']

$twitter_callback_url = "http://127.0.0.1/twitter_callback"
$consumer = OAuth::Consumer.new(
    ENV['FABUNIAO_TWITTER_CONSUMER_KEY'],
    ENV['FABUNIAO_TWITTER_CONSUMER_SECRET'], 
    :site => 'http://api.twitter.com')

Twitter.configure do |config|
    config.consumer_key = ENV['FABUNIAO_TWITTER_CONSUMER_KEY']
    config.consumer_secret = ENV['FABUNIAO_TWITTER_CONSUMER_SECRET']
end

# Logger
use Rack::Logger
$logger = Logger.new('logs/fabuniao.log')
$logger.level = Logger::DEBUG

before do
    $logger.debug('------------------------------------')
end

get '/' do
    client = WeiboOAuth2::Client.new
    if session[:access_token] && !client.authorized?
        token = client.get_token_from_hash({:access_token => session[:access_token], :expires_at => session[:expires_at]}) 
        p token.inspect
        p token.validated?

        unless token.validated?
            reset_session
            redirect '/weibo'
            return
        end
    end
    if session[:uid]
        @user = client.users.show_by_uid(session[:uid]) 
        @statuses = client.statuses
    end
    haml :index
end

get '/weibo' do
    client = WeiboOAuth2::Client.new
    redirect client.authorize_url
end

get '/weibo_callback' do
    client = WeiboOAuth2::Client.new
    access_token = client.auth_code.get_token(params[:code].to_s)
    session[:test] = access_token.params["uid"]
    session[:uid] = access_token.params["uid"]
    session[:access_token] = access_token.token
    session[:expires_at] = access_token.expires_at
    @user = client.users.show_by_uid(session[:uid].to_i)
    redirect '/'
end

get '/twitter' do
    $request_token = $consumer.get_request_token(:oauth_callback => "http://127.0.0.1/twitter_callback")
    $logger.debug("request_token")
    $logger.debug($request_token)
    session[:request_token] = $request_token
    redirect $request_token.authorize_url(:oauth_callback => "http://127.0.0.1/twitter_callback")
end

get '/twitter_callback' do
    $access_token = session[:request_token].get_access_token
    $logger.debug("access_token")
    $logger.debug($access_token)
    twitter_client = Twitter::Client.new(
        :oauth_token => $access_token.token,
        :oauth_token_secret => $access_token.secret,
    )
    twitter_client.update("Testing via twiiter api.")
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
    client = WeiboOAuth2::Client.new
    client.get_token_from_hash({:access_token => session[:access_token], :expires_at => session[:expires_at]}) 
    statuses = client.statuses

    unless params[:file] && (tmpfile = params[:file][:tempfile]) && (name = params[:file][:filename])
        statuses.update(params[:status])
    else
        status = params[:status] || '图片'
        pic = File.open(tmpfile.path)
        statuses.upload(status, pic)
    end

    redirect '/'
end

helpers do 
    def reset_session
        session[:uid] = nil
        session[:access_token] = nil
        session[:expires_at] = nil
    end
end
