require 'http'
require 'dotenv/load'

# 取得授權
class AccessTokenService
  def initialize
    @url = 'https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token'

    @client_id = ENV['TDX_CLIENT_ID']
    @client_secret = ENV['TDX_CLIENT_SECRET']
  end

  def call
    response = HTTP.post(@url, form: {
                           'grant_type' => 'client_credentials',
                           'client_id' => @client_id,
                           'client_secret' => @client_secret
                         }).parse
    response['access_token']
  end
end
