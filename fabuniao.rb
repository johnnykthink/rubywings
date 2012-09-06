# -*- coding: utf-8 -*-

require 'rubygems'
require 'weibo_2'
require 'time-ago-in-words'

%w(rubygems bundler).each { |dependency| require dependency }
Bundler.setup
%w(sinatra haml sass).each { |dependency| require dependency }
enable :sessions
#use Rack::Session::Pool, :expire_after => 2592000

WeiboOAuth2::Config.api_key = ENV['FABUNIAO_API_KEY']
WeiboOAuth2::Config.api_secret = ENV['FABUNIAO_API_SECRET']
WeiboOAuth2::Config.redirect_uri = ENV['FABUNIAO_REDIRECT_URI']

# Logger
use Rack::Logger
$logger = Logger.new('logs/fabuniao.log')
$logger.level = Logger::DEBUG

before do
    $logger.debug(ENV['FABUNIAO_API_KEY'])
end

get '/' do
    client = WeiboOAuth2::Client.new
    if session[:access_token] && !client.authorized?
        token = client.get_token_from_hash({:access_token => session[:access_token], :expires_at => session[:expires_at]}) 
        p token.inspect
        p token.validated?

        unless token.validated?
            reset_session
            redirect '/connect'
            return
        end
    end
    if session[:uid]
        @user = client.users.show_by_uid(session[:uid]) 
        @statuses = client.statuses
    end
    haml :index
end

get '/connect' do
    client = WeiboOAuth2::Client.new
    redirect client.authorize_url
end

get '/callback' do
    client = WeiboOAuth2::Client.new
    access_token = client.auth_code.get_token(params[:code].to_s)
    session[:test] = access_token.params["uid"]
    session[:uid] = access_token.params["uid"]
    session[:access_token] = access_token.token
    session[:expires_at] = access_token.expires_at
    @user = client.users.show_by_uid(session[:uid].to_i)
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
