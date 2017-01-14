require "httparty"
require "json"
require "optionparser"

options = {}

OptionParser.new do |opts|
  opts.on("--simulate PATH") do |sim|
    options[:simulate] = sim
  end
end.parse!

# Read in the secrets from the vars.config file and set as attributes
@vars = JSON.parse(File.read("vars.json"))

@pagerduty = @vars["pagerduty"]
@wireless_tags = @vars["wireless_tags"]

# default to standard api url if none given in vars.config
@wireless_tags["url"] = @wireless_tags.has_key?("url") ? @vars["wireless_tags"]["url"] : "https://mytaglist.com"
@pagerduty["url"] = @pagerduty.has_key?("url") ? @vars["pagerduty"]["url"] : "https://api.pagerduty.com"

def self.arm_system(cookie, id)
  body = {
    "id":id
  }

  resp = HTTParty.post(
    "#{@wireless_tags["url"]}/ethClient.asmx/ArmAll",
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
    "#{@wireless_tags["url"]}/ethClient.asmx/DisarmAll",
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
    @vars["health_check"]["url"],
  )

  self.validate_response(resp)
end

def self.wireless_tags_sign_in(email, password)
  body = {
      :email => email,
      :password => password
  }

  resp = HTTParty.post(
    "#{@wireless_tags["url"]}/ethAccount.asmx/SignIn",
    :body => body.to_json,
    :headers => { 
      "Content-Type" => "application/json; charset=utf-8",
      "Content-Length" => "#{body.to_json.length}" 
    }
  )

  self.validate_response(resp)

  cookie = resp.headers["set-cookie"]

  File.open("cookie", "wb") do |output|
    output.write(cookie)
  end

  return cookie
end

def self.wireless_tags_is_signed_in(cookie)
  resp = HTTParty.post(
    "#{@wireless_tags["url"]}/ethAccount.asmx/IsSignedIn",
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
    "#{@pagerduty["url"]}/oncalls",
    :headers => {
      "Accept" => "application/vnd.pagerduty+json;version=2",
      "Authorization" => "Token token=fLKofhk73AwW3Md2yh_P"
    },
    :query => {
      "time_zone" => "EST",
      "user_ids" => ["PQW6XH7"],
      "escalation_policy_ids" => ["PJXN8C6"],
      "schedule_ids" => ["PWS2SK2"],
      "until" => "#{Time.now + (60 * 60 * 24 * 50)}"
    }
  )

  self.validate_response(resp)

  scheduled = resp["oncalls"][0]

  if scheduled == nil
    puts "no on call found for the time period specified - #{Time.now} to #{Time.now + (60 * 60 * 24 * 50)}"
  else
    on_call_start = scheduled["start"]
  end

  return on_call_start
end

def self.system_status(cookie)
  resp = HTTParty.post(
    "#{@wireless_tags["url"]}/ethClient.asmx/GetTagList",
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
    puts "ERROR: #{resp.parsed_response["Message"]} - exiting script"
    exit 1
  end
end

# Check to see if the login "cookie" exists on the system already
if File.exists?("cookie")
  cookie = File.read("cookie")
  
  # Check to see if the login "cookie" is still valid
  logged_in = wireless_tags_is_signed_in(cookie)
    # If it's not then login again and save the cookie to the system
    unless logged_in
      cookie = wireless_tags_sign_in(@wireless_tags["email"], @wireless_tags["password"])
    end
else
  # Login and set "cookie" if not logged in already
  cookie = wireless_tags_sign_in(@wireless_tags["email"], @wireless_tags["password"])
end

# Check to see if I'm on call yet 
on_call_start = DateTime.rfc3339(on_call(@pagerduty["api_token"], @pagerduty["user_id"], @pagerduty["escalation_policy_id"], @pagerduty["schedule_id"])).to_time

if on_call_start.nil?
  puts "ERROR: No oncall start time detected - check what the pagerduty api is returning"
  exit 1
end

simulate_on_call = options.has_key?(:simulate) && options[:simulate] == "oncall"
simulate_off_call = options.has_key?(:simulate) && options[:simulate] == "offcall"

if simulate_on_call
  on_call_start = Time.now + (-60)
elsif simulate_off_call
  on_call_start = Time.now + (60)
elsif options.has_key?(:simulate) && (options[:simulate] != "oncall" || options[:simulate] != "offcall")
  puts "please pass only 'oncall' or 'offcall' for the --simulate flag"
  exit 1
end

if Time.now >= on_call_start
  puts "you're on call"
  # Check the status of the system (eventState = 0 means "disarmed")
  system_status(cookie).each do |x| 
    if x["event_state"] == 0
      puts "#{x["tag_name"]} disarmed -#{ ' (simulated)' if simulate_on_call } arming now"
      arm_system(cookie, x["id"]) unless simulate_on_call
    else
      puts "#{x["tag_name"]} already armed"
    end
  end
else
  puts "not on call yet"
  system_status(cookie).each do |x|
    if x["event_state"] == 0
      puts "#{x["tag_name"]} already disarmed"
    else
      puts "#{x["tag_name"]} armed -#{ ' (simulated)' if simulate_off_call } disarming now"
      disarm_system(cookie, x["id"]) unless simulate_off_call
    end
  end
end

# Hit the health check endpoint as the last step
health_check unless simulate_on_call || simulate_off_call
