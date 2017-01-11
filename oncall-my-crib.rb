require "httparty"
require "json"

# Check Pagerduty Schedule to see if I'm on call yet or if a new override has been set
  # save the start and end dates to the schedule

# If I'm not on call
  # system already disarmed - don't do anything
  # system armed - turn it off
# Else
  # system disarmed - turn it on
  # system armed - don't do anything

# report to healthchecks.io endpoint to let me know the script is still running as expected every 5 minutes

@mytags_email = ""
@mytags_password = ""
@mytags_url = "https://mytaglist.com"
@pd_api_token = ""
@pd_escalation_policy_id = [""]
@schedule_id = [""]
@pd_user_id = [""]

def arm_system

end

def disarm_system

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
  resp = HTTParty.get(
    "https://api.pagerduty.com/oncalls",
    :headers => {
      "Accept" => "application/vnd.pagerduty+json;version=2",
      "Authorization" => "Token token=#{api_token}"
    },
    :query => {
      "time_zone" => "UTC",
      "user_ids" => user_ids,
      "escalation_policy_ids" => escalation_policy_ids,
      "schedule_ids" => schedule_ids,
      "until" => "#{Time.now + (60 * 60 * 24 * 60)}"
    }
  )["oncalls"][0]

  on_call_times = {}
  on_call_times["start"] = resp["start"]
  on_call_times["end"] = resp["end"]

  return on_call_times
end

# Check to see if the login "cookie" exists on the system already
if File.exists?("cookie")
  cookie = File.read("cookie")
  
  # Check to see if the login "cookie" is still valid
  logged_in = mytags_is_signed_in(cookie)
    # If it's not then login again and save the cookie to the system
    unless logged_in
      mytags_sign_in(@mytags_email, @mytags_password)
    end
else
  # Login and set "cookie" if not logged in already
  mytags_sign_in(@mytags_email, @mytags_password)
end

# Check to see if I'm on call yet
on_call_times = on_call(@pd_api_token, @pd_user_id, @pd_escalation_policy_id, @schedule_id)
on_call_start = DateTime.rfc3339(on_call_times["start"]).to_time.utc
on_call_end = DateTime.rfc3339(on_call_times["end"]).to_time.utc

if Time.now.utc >= on_call_start
  # puts "you're on call!"
end


# Hit the health check endpoint as the last step
