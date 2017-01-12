require "httparty"
require "json"

# report to healthchecks.io endpoint to let me know the script is still running as expected every 5 minutes

@mytags_email = ""
@mytags_password = ""
@mytags_url = "https://mytaglist.com"
@pd_api_token = ""
@pd_escalation_policy_id = [""]
@pd_schedule_id = [""]
@pd_url = "https://api.pagerduty.com"
@pd_user_id = [""]

def arm_system(cookie)
  HTTParty.post(
    "#{@mytags_url}/ethClient.asmx/ArmAll",
    :headers => {
      "Content-Type" => "application/json; charset=utf-8",
      "Content-Length" => "0",
      "cookie" => cookie
    }
  )["d"]
end

def disarm_system(cookie)
  HTTParty.post(
    "#{@mytags_url}/ethClient.asmx/DisarmAll",
    :body => {
      "autoRetry":true
    }.to_json,
    :headers => {
      "Content-Type" => "application/json; charset=utf-8",
      "Content-Length" => "16",
      "cookie" => cookie
    }
  )
end

def health_check

end

def mytags_sign_in(email, password)
  body = {
      :email => email,
      :password => password
  }

  cookie = HTTParty.post(
    "#{@mytags_url}/ethAccount.asmx/SignIn",
    :body => body.to_json,
    :headers => { 
      "Content-Type" => "application/json; charset=utf-8",
      "Content-Length" => "#{body.to_json.length}" 
    }
  ).headers["set-cookie"]

  File.open("cookie", "wb") do |output|
    output.write(cookie)
  end

  return cookie
end

def mytags_is_signed_in(cookie)
  HTTParty.post(
    "#{@mytags_url}/ethAccount.asmx/IsSignedIn",
    :headers => { 
      "Content-Type" => "application/json; charset=utf-8",
      "Content-Length" => "0",
      "cookie" => cookie
    }
  )["d"]
end

def on_call(api_token, user_ids, escalation_policy_ids, schedule_ids)
  # Check the regular on call schedule for on call times
  scheduled = HTTParty.get(
    "https://api.pagerduty.com/oncalls",
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
  )["oncalls"][0]

  next_on_call_times = {}

  if scheduled == nil
    puts "no on call found for the time period specified - #{Time.now} to #{Time.now + (60 * 60 * 24 * 50)}"
  else
    next_on_call_times["start"] = scheduled["start"]
    next_on_call_times["end"] = scheduled["end"]
  end

  return next_on_call_times
end

def system_status(cookie)
  resp = HTTParty.post(
    "#{@mytags_url}/ethClient.asmx/GetTagList",
    :headers => {
      "Content-Type" => "application/json; charset=utf-8",
      "Content-Length" => "0",
      "cookie" => cookie
    }
  )["d"]

  status = []
  resp.each do |x|
    status << x["eventState"]
  end

  return status
end

# Check to see if the login "cookie" exists on the system already
if File.exists?("cookie")
  cookie = File.read("cookie")
  
  # Check to see if the login "cookie" is still valid
  logged_in = mytags_is_signed_in(cookie)
    # If it's not then login again and save the cookie to the system
    unless logged_in
      cookie = mytags_sign_in(@mytags_email, @mytags_password)
    end
else
  # Login and set "cookie" if not logged in already
  cookie = mytags_sign_in(@mytags_email, @mytags_password)
end

# Check to see if I'm on call yet
on_call_times = on_call(@pd_api_token, @pd_user_id, @pd_escalation_policy_id, @pd_schedule_id)
on_call_start = DateTime.rfc3339(on_call_times["start"]).to_time
# Uncomment the line below to simulate being on call to test system arming
# on_call_start = DateTime.rfc3339("2017-01-11T19:02:01-05:00").to_time
on_call_end = DateTime.rfc3339(on_call_times["end"]).to_time

if Time.now >= on_call_start
  puts "you're on call"
  # Check the status of the system (eventState = 0 means "disarmed")
  if system_status(cookie).include? 0
    puts "arming the system"
    arm_system(cookie)
  else
    puts "system already armed...doing nothing"
  end
else
  puts "not on call yet"
  if system_status(cookie).include? 0
    puts "system already disarmed...doing nothing"
  else
    puts "disarming the system"
    disarm_system(cookie)
  end
end

# Hit the health check endpoint as the last step
