require 'dotenv/load'

Dir['./initializers/*.rb'].each { |file| require file }
Dir['./services/*.rb'].each { |file| require file }
Dir['./workers/*.rb'].each { |file| require file }

require './app'
