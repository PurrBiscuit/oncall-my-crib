require "httparty"
require "json"

# Login Process
# check to see if cookie exists on file system
  # if it doesn't then sign in
  # if it does
    # check to see if the cookie is still valid by checking the "IsSignedIn" API endpoint with it
      # if it is then continue with the rest of the script
      # if it isn't then delete the old cookie, sign on using "SignIn" endpoint, and then save the new cookie to somewhere on the file system

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
@url = "https://mytaglist.com"

def sign_in(email, password)
  body = {
      :email => email,
      :password => password
  }

  cookie = HTTParty.post(
    "#{@url}/ethAccount.asmx/SignIn",
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

def is_signed_in(cookie)
  HTTParty.post(
    "#{@url}/ethAccount.asmx/IsSignedIn",
    :headers => { 
      "Content-Type" => "application/json; charset=utf-8",
      "Content-Length" => "0",
      "cookie" => cookie
    }
  )["d"]
end

def arm_system

end

def disarm_system

end

def check_on_call

end

# Check to see if the login "cookie" exists on the system already
if File.exists?("cookie")
  cookie = File.read("cookie")
  
  # Check to see if the login "cookie" is still valid
  logged_in = is_signed_in(cookie)
    # If it's not then login again and save the cookie to the system
    unless logged_in
      sign_in(@mytags_email, @mytags_password)
    end
else
  # Login and set "cookie" if not logged in already
  sign_in(@email, @password)
end

# Check to see if I'm on call yet

