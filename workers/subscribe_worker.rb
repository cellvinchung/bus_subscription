require 'sendgrid-ruby'
Dir['./services/*.rb'].each { |file| require file }
require_relative '../app'

class SubscribeWorker
  include Sidekiq::Worker
  include SendGrid

  def perform(redis_key)
    opts = Oj.load(redis.get(redis_key))
    @route_no = opts['route_no']
    @direction = opts['direction']
    @target_stop_id = opts['stop_id']
    @emails = opts['emails']

    @all_stops = Oj.load(redis.get("stops_#{@route_no}")).find do |stops|
                   stops['direction'] == @direction.to_i
                 end['stops']

    loop do
      sleep(10)
      puts '還沒有'
      break unless approaching_status == '未接近'
    end

    # 寄信
    from = SendGrid::Email.new(email: 'cellvinchung@gmail.com')

    stop_name = @all_stops.find { |stop| stop['stop_id'] == @target_stop_id }['name']

    if approaching_status == '接近中'
      subject = "#{@route_no}路線公車即將到 #{stop_name}"
      text = "#{@route_no} 距離 #{stop_name} 還有 3 ~ 5 站"
    else
      subject = "目前沒有 #{@route_no} 路線車輛開往 #{stop_name}"
      text = '可能尚未發車或末班車已過'
    end

    content = SendGrid::Content.new(type: 'text/html', value: "<p>#{text}</p>")

    begin
      puts '準備寄信'
      @emails.each do |email|
        to = SendGrid::Email.new(email: email)
        message = SendGrid::Mail.new(from, subject, to, content)

        response = sendgrid_client.client.mail._('send').post(request_body: message.to_json)

        puts "status_code #{response.status_code}"
      end

    rescue Exception => e
        puts e.message
    end
    redis.del(redis_key)
  end

  def approaching_status
    responses = []
    BusSubscription::LOCATIONS.each do |location|
      response = HTTP.auth("Bearer #{access_token}").get("https://tdx.transportdata.tw/api/basic/v2/Bus/RealTimeNearStop/City/#{location}/#{@route_no}",
                                                         params: {
                                                           '$filter' => "Direction eq '#{@direction.to_i}'"
                                                         })

      return response.to_s['message'] if response.code != 200

      responses += Oj.load(response.to_s)
    end

    # responses.to_json
    list = responses.map do |bus|
      {
        'stop_id' => bus['StopID'],
        'stop_name' => bus['StopName']['Zh_tw'],
        'plate_no' => bus['PlateNumb']
      }
    end

    current_stops = list.pluck('stop_id')
    all_stop_ids = @all_stops.pluck('stop_id')

    current_stops.each do |current_stop|
      diff_count = all_stop_ids.index(@target_stop_id) - all_stop_ids.index(current_stop)

      @status = if diff_count < 0
                  '未發車'
                elsif (3..5).include?(diff_count)
                  '接近中'
                else
                  '未接近'
                end
    end

    @status
  end

  def access_token
    @access_token ||= AccessTokenService.new.call
  end

  def redis
    @redis ||= Redis.new(url: ENV['REDIS_URL'])
  end

  def sendgrid_client
    @sendgrid_client ||= SendGrid::API.new(api_key: ENV['SENDGRID_API_KEY'])
  end
end
