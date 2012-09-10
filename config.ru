# -*- coding: utf-8 -*-

require './rubywings.rb'

set :session_secret, 'i am a secret'

run Sinatra::Application
