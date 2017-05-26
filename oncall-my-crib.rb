require "httparty"
require "json"
require "optionparser"
require "time"

options = {}

OptionParser.new do |opts|
  opts.on("--simulate PATH") do |sim|
    options[:simulate] = sim
  end
end.parse!

required_env_vars = [
  "ONCALL_HEALTH_CHECK_URL",
  "ONCALL_PD_API_TOKEN",
  "ONCALL_PD_USER_ID",
  "ONCALL_PD_ESCALATION_POLICY_ID",
  "ONCALL_PD_SCHEDULE_ID",
  "ONCALL_WIRELESS_TAGS_EMAIL",
  "ONCALL_WIRELESS_TAGS_PASSWORD"
]

@wireless_tags_url = "https://mytaglist.com"
@pagerduty_url = "https://api.pagerduty.com"

def self.arm_system(cookie, id)
  body = {
    "id":id
  }

  resp = HTTParty.post(
    "#{@wireless_tags_url}/ethClient.asmx/ArmAll",
    :body => body.to_json,
    :headers => {
      "Content-Type" => "application/json; charset=utf-8",
      "Content-Length" => "#{body.to_json.length}",
      "cookie" => cookie
    }
  )

  self.validate_response(resp)
end

def self.disarm_system(cookie, id)
  body = {
    "id":id,
    "autoRetry": true
  }

  resp = HTTParty.post(
    "#{@wireless_tags_url}/ethClient.asmx/DisarmAll",
    :body => body.to_json,
    :headers => {
      "Content-Type" => "application/json; charset=utf-8",
      "Content-Length" => "#{body.to_json.length}",
      "cookie" => cookie
    }
  )

  self.validate_response(resp)
end

def health_check
  resp = HTTParty.get(
    ENV["ONCALL_HEALTH_CHECK_URL"],
  )

  self.validate_response(resp)
end

def self.log(message)
  puts "#{Time.now.iso8601} - #{message}"
end

def self.wireless_tags_sign_in(email, password)
  body = {
      :email => email,
      :password => password
  }

  resp = HTTParty.post(
    "#{@wireless_tags_url}/ethAccount.asmx/SignIn",
    :body => body.to_json,
    :headers => { 
      "Content-Type" => "application/json; charset=utf-8",
      "Content-Length" => "#{body.to_json.length}" 
    }
  )

  self.validate_response(resp)

  cookie = resp.headers["set-cookie"]

  File.open("oncallmycrib-cookie", "wb") do |output|
    output.write(cookie)
  end

  return cookie
end

def self.wireless_tags_is_signed_in(cookie)
  resp = HTTParty.post(
    "#{@wireless_tags_url}/ethAccount.asmx/IsSignedIn",
    :headers => { 
      "Content-Type" => "application/json; charset=utf-8",
      "Content-Length" => "0",
      "cookie" => cookie
    }
  )

  self.validate_response(resp)

  return resp["d"]
end

def self.on_call(api_token, user_ids, escalation_policy_ids, schedule_ids)
  # Check the regular on call schedule for on call times
  resp = HTTParty.get(
    "#{@pagerduty_url}/oncalls",
    :headers => {
      "Accept" => "application/vnd.pagerduty+json;version=2",
      "Authorization" => "Token token=#{api_token}"
    },
    :query => {
      "time_zone" => "EST",
      "user_ids" => user_ids,
      "escalation_policy_ids" => escalation_policy_ids,
      "schedule_ids" => schedule_ids,
      "until" => "#{Time.now + (60 * 60 * 24 * 50)}"
    }
  )

  self.validate_response(resp)

  scheduled = resp["oncalls"][0]

  if scheduled == nil
    return nil
  else
    on_call_start = scheduled["start"]
    return on_call_start
  end
end

def self.system_status(cookie)
  resp = HTTParty.post(
    "#{@wireless_tags_url}/ethClient.asmx/GetTagList",
    :headers => {
      "Content-Type" => "application/json; charset=utf-8",
      "Content-Length" => "0",
      "cookie" => cookie
    }
  )

  self.validate_response(resp)

  status_response = resp["d"]

  status = []
  status_response.each do |x|
     if x["comment"] == "oncall" 
      status_hash = {}
      status_hash["tag_name"] = x["name"]
      status_hash["event_state"] = x["eventState"]
      status_hash["id"] = x["slaveId"]
      status << status_hash
    end
  end

  return status
end

def self.validate_response(resp)
  if resp.response.class != Net::HTTPOK
    log("ERROR: #{resp.parsed_response["Message"]} - exiting script")
    exit 1
  end
end

def self.vars_check(env_vars)
  missing_vars = []

  env_vars.each do |var|
    unless ENV.has_key?(var)
      missing_vars << var
    end
  end

  unless missing_vars.empty?
    self.log("ERROR: need to set the #{missing_vars.join(", ")} env var(s) before continuing")
    exit 1
  end
end

# check if require env vars have been set
vars_check(required_env_vars)

# Check to see if the login "cookie" exists on the system already
if File.exists?("oncallmycrib-cookie")
  cookie = File.read("oncallmycrib-cookie")
  
  # Check to see if the login "cookie" is still valid
  logged_in = wireless_tags_is_signed_in(cookie)
    # If it's not then login again and save the cookie to the system
    unless logged_in
      cookie = wireless_tags_sign_in(ENV["ONCALL_WIRELESS_TAGS_EMAIL"], ENV["ONCALL_WIRELESS_TAGS_PASSWORD"])
    end
else
  # Login and set "cookie" if not logged in already
  cookie = wireless_tags_sign_in(ENV["ONCALL_WIRELESS_TAGS_EMAIL"], ENV["ONCALL_WIRELESS_TAGS_PASSWORD"])
end

# Check to see if I'm on call yet 
on_call_check = on_call(
  ENV["ONCALL_PD_API_TOKEN"], 
  ["#{ENV['ONCALL_PD_USER_ID']}"], 
  ["#{ENV['ONCALL_PD_ESCALATION_POLICY_ID']}"], 
  ["#{ENV['ONCALL_PD_SCHEDULE_ID']}"]
)

on_call_start = DateTime.rfc3339(on_call_check).to_time unless on_call_check.nil?

if on_call_start.nil?
  log("no oncall start time detected - assuming offcall for now")
  on_call_start = Time.now + (60)
end

simulate_on_call = options.has_key?(:simulate) && options[:simulate] == "oncall"
simulate_off_call = options.has_key?(:simulate) && options[:simulate] == "offcall"

if simulate_on_call
  on_call_start = Time.now + (-60)
elsif simulate_off_call
  on_call_start = Time.now + (60)
elsif options.has_key?(:simulate) && (options[:simulate] != "oncall" || options[:simulate] != "offcall")
  log("ERROR: please pass only 'oncall' or 'offcall' for the --simulate flag")
  exit 1
end

if Time.now >= on_call_start
  log("you're on call")
  # Check the status of the system (eventState = 0 means "disarmed")
  system_status(cookie).each do |x| 
    if x["event_state"] == 0
      log("#{x["tag_name"]} disarmed -#{ ' (simulated)' if simulate_on_call } arming now")
      arm_system(cookie, x["id"]) unless simulate_on_call
    else
      log("#{x["tag_name"]} already armed")
    end
  end
else
  log("not on call yet")
  system_status(cookie).each do |x|
    if x["event_state"] == 0
      log("#{x["tag_name"]} already disarmed")
    else
      log("#{x["tag_name"]} armed -#{ ' (simulated)' if simulate_off_call } disarming now")
      disarm_system(cookie, x["id"]) unless simulate_off_call
    end
  end
end

# Hit the health check endpoint as the last step
health_check unless simulate_on_call || simulate_off_call
