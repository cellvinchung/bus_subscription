require 'sinatra/base'
require 'active_support/all'
require 'http'
require 'oj'
require 'redis'
require 'dotenv/load'

class BusSubscription < Sinatra::Base
  enable :sessions, :logging, :dump_errors
  # 雙北地區
  LOCATIONS = %w[Taipei NewTaipei]

  before do
    @responses = []

    content_type :json
  end

  # 路線列表
  get '/routes' do
    cache_routes_list
  end

  # 路線站牌列表
  get '/stops/:route_no' do
    @route_no = params[:route_no]

    cache_stops_list
  end

  post '/subscribe' do
    @emails = params[:emails]
    return '請提供至少一組email' if @emails.blank?

    @direction = params[:direction] # 去、返程

    return 'direction 只能為0(去程)或1(返程)' unless %w[0 1].include?(@direction.to_s)

    @route_no = params[:route_no] # 路線

    return 'route_no 不存在' if Oj.load(cache_routes_list).find { |route| route['route_en'] == @route_no }.nil?

    target_stop_id = params[:stop_id].to_s # 站牌

    @all_stop_ids = Oj.load(cache_stops_list).find do |stops|
                      stops['direction'] == @direction.to_i
                    end['stops'].pluck('stop_id')

    return '站牌不存在' if @all_stop_ids.exclude?(target_stop_id)

    # params[:bus_plate] # 車牌

    redis_key = SecureRandom.hex
    opts = {
      locations: LOCATIONS,
      route_no: @route_no,
      direction: @direction,
      stop_id: target_stop_id,
      emails: @emails
    }
    redis.set(redis_key, opts.to_json)
    SubscribeWorker.perform_async(redis_key)

    return { message: '已訂閱' }.to_json
  end

  def cache_routes_list
    @redis_key = 'routes'
    return redis.get(@redis_key) if redis.get(@redis_key).present?

    LOCATIONS.each do |location|
      response = HTTP.auth("Bearer #{access_token}").get("https://tdx.transportdata.tw/api/basic/v2/Bus/Route/City/#{location}")

      return response.to_s['message'] if response.code != 200

      @responses += Oj.load(response.to_s)
    end

    return { error: '查無資料' }.to_json if @responses.blank?

    list = @responses.map do |route|
      {
        'route_en' => route['RouteName']['En'],
        'route_no' => route['RouteName']['Zh_tw']
      }
    end
    redis.set(@redis_key, list.to_json)
    redis.expire(@redis_key, 1.day.to_i)

    list.to_json
  end

  def cache_stops_list
    return 'route_no 必須存在' if @route_no.blank?

    @redis_key = "stops_#{@route_no}"
    return redis.get(@redis_key) if redis.get(@redis_key).present?

    LOCATIONS.each do |location|
      response = HTTP.auth("Bearer #{access_token}").get("https://tdx.transportdata.tw/api/basic/v2/Bus/DisplayStopOfRoute/City/#{location}/#{@route_no}", params: {
                                                           '$filter' => "RouteName/Zh_tw eq '#{@route_no}'"
                                                         })

      return response.to_s['message'] if response.code != 200

      @responses += Oj.load(response.to_s)
    end

    return { error: '查無此路線' }.to_json if @responses.blank?

    list = @responses.map do |direction|
      if direction['Stops'].present?
        stops = direction['Stops'].map do |stop_data|
          {
            'stop_id' => stop_data['StopID'],
            'name' => stop_data['StopName']['Zh_tw']
          }
        end
      end

      {
        'direction' => direction['Direction'],
        'stops' => stops
      }
    end

    redis.set(@redis_key, list.to_json)
    redis.expire(@redis_key, 1.day.to_i)

    list.to_json
  end

  def redis
    @redis ||= Redis.new(url: ENV['REDIS_URL'])
  end

  def access_token
    @access_token ||= AccessTokenService.new.call
  end
end
