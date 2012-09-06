# -*- coding: utf-8 -*-

require './fabuniao.rb'

set :session_secret, 'i am a secret'

run Sinatra::Application
