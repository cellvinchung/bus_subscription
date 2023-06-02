# 雙北公車訂閱通知 API
輸入路線、方向、站牌、email，到站前 3 ~ 5 站寄送通知至 email

## 系統需求
- redis
- ruby 3.2.2

## 事先準備
1. 補足下列環境變數資訊
   1. `REDIS_URL` redis 路徑，如 `redis://127.0.0.1:6379`
   2. `TDX_CLIENT_ID` [交通部 TDX 平台](https://tdx.transportdata.tw/) api client id
   3. `TDX_CLIENT_SECRET` [交通部 TDX 平台](https://tdx.transportdata.tw/) api client secret
   4. `SENDGRID_API_KEY` [sendgrid](https://app.sendgrid.com/) api key
2. clone 本專案
3. cd 進 專案 執行 `rackup`，另開 termianl 執行 `bundle exec sidekiq -r ./workers/subscribe_worker.rb`
   - 若已有安裝 [foreman](https://github.com/ddollar/foreman) ，可直接執行 `forman start`

## 使用方式

1. 先取得路線之站牌 ID
   - GET `http://127.0.0.1:9292/stops/:route_no` :route_no 為路線號碼
   - response
   -  [以路線 672 為例](https://github.com/cellvinchung/bus_subscription/blob/master/example/stops.json)

2. 訂閱通知
   - 參數

   | 名稱 | 說明 |
   | --- | --- |
   | route_no | 路線號碼 |
   | direction | 方向。 0 為去程，1為返程 |
   | stop_id | 站牌 ID |
   | emails | 通知信箱，可以陣列格式設多組 |

   - POST `http://127.0.0.1:9292/subscribe`
