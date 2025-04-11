<#
.SYNOPSIS
PowerShell script to test security controls using Selenium WebDriver
#>

# ----------------------
# Configuration Section
# ----------------------
$EMAIL = "kk1344@live.mdx.ac.uk"
$PASSWORD = "Oct242001%"




credit card - "[
  {
    "type": "American Express",
    "name": "Duncan Corkery",
    "number": "379611559804478",
    "cvv": "282",
    "expiry": "10/26"
  },
  {
    "type": "American Express",
    "name": "Mr. Kip Goodwin PhD",
    "number": "346076997707644",
    "cvv": "657",
    "expiry": "05/25"
  },
  {
    "type": "American Express",
    "name": "Antwan Stroman DDS",
    "number": "344926502978696",
    "cvv": "358",
    "expiry": "05/26"
  },
  {
    "type": "American Express",
    "name": "Shaniya Will",
    "number": "340336113847294",
    "cvv": "641",
    "expiry": "10/27"
  },
  {
    "type": "American Express",
    "name": "Jordon Swift",
    "number": "347178102980451",
    "cvv": "223",
    "expiry": "11/25"
  }
]"



$TEST_URLS = @(
    @{
        url = "https://www.office.com/login?es=UnauthClick&ru=%2f"
        name = "Office Portal"
    },
    @{
        url = "https://portal.azure.com/"
        name = "Azure Portal"
    }
)

$FAILURE_CONDITIONS = @{
    invalid_credentials = @{
        priority = 1
        elements = @(
            @{
                selector = '#usernameError'
                text = "Your account or password is incorrect"
                partial_match = $true
            }
        )
        phrases = @(
            "your account or password is incorrect"
            "reset it now"
        )
    }
}

# Load Selenium Assemblies



# ----------------------
# Core Functions
# ----------------------

function Initialize-Driver {
    Write-Host "🛠️ Initializing Firefox driver..."
    try {
        # Load Selenium WebDriver assemblies

        # Configure Firefox options
        $options = New-Object OpenQA.Selenium.Firefox.FirefoxOptions
        # $options.BinaryLocation = $FIREFOX_BINARY_PATH
        $options.SetPreference("dom.webdriver.enabled", $false)
        $options.SetPreference("useAutomationExtension", $false)
        
        # Configure driver service
        $service = [OpenQA.Selenium.Firefox.FirefoxDriverService]::CreateDefaultService()
        $service.FirefoxBinaryPath = $FIREFOX_BINARY_PATH
        
        # Create driver instance
        $driver = New-Object OpenQA.Selenium.Firefox.FirefoxDriver($service, $options)
        Write-Host "✅ Driver initialized successfully"
        return $driver
    }
    catch {
        Write-Host "❌ Driver initialization failed: $_"
        Write-Host $_.ScriptStackTrace
        return $null
    }
}

function Check-FailureConditions {
    param(
        [OpenQA.Selenium.IWebDriver]$Driver
    )
    
    Write-Host "🔍 Checking failure conditions..."
    try {
        $pageText = $Driver.PageSource.ToLower()
        Write-Host "Page text sample: $($pageText.Substring(0, [Math]::Min(200, $pageText.Length)))..."

        # Check for invalid credentials
        if ($pageText -match "your account or password is incorrect" -or $pageText -match "reset it now") {
            Write-Host "⚠️ Invalid credentials detected"
            return @(@{ condition = "invalid_credentials" })
        }

        Write-Host "✅ No failure conditions detected"
        return @()
    }
    catch {
        Write-Host "❌ Error checking conditions: $_"
        return @()
    }
}

function Handle-Login {
    param(
        [OpenQA.Selenium.IWebDriver]$Driver,
        [hashtable]$TestUrl
    )
    
    Write-Host "`n🚀 Starting test for: $($TestUrl.name) ($($TestUrl.url))"
    try {
        # Load URL
        Write-Host "🌐 Navigating to $($TestUrl.url)"
        $Driver.Navigate().GoToUrl($TestUrl.url)
        
        # Wait for page to fully load
        $wait = New-Object OpenQA.Selenium.Support.UI.WebDriverWait($Driver, [System.TimeSpan]::FromSeconds(20))
        $wait.Until([Func[OpenQA.Selenium.IWebDriver, bool]]{ 
            param($d)
            return $d.ExecuteScript("return document.readyState") -eq "complete"
        }) | Out-Null
        Write-Host "✅ Page fully loaded"
        
        # Wait for email field
        Write-Host "📧 Waiting for email field"
        $emailField = $wait.Until([OpenQA.Selenium.Support.UI.ExpectedConditions]::ElementIsVisible(
            [OpenQA.Selenium.By]::CssSelector("input[type='email']")
        ))
        
        # Enter email
        Write-Host "📧 Entering email"
        $emailField.SendKeys($EMAIL)
        
        # Click Next
        Write-Host "➡️ Clicking Next"
        $nextButton = $wait.Until([OpenQA.Selenium.Support.UI.ExpectedConditions]::ElementToBeClickable(
            [OpenQA.Selenium.By]::CssSelector("input[type='submit'][value='Next']")
        ))
        $nextButton.Click()
        
        # Wait for password field
        Write-Host "🔑 Waiting for password field"
        $passwordField = $wait.Until([OpenQA.Selenium.Support.UI.ExpectedConditions]::ElementIsVisible(
            [OpenQA.Selenium.By]::CssSelector("input[type='password']")
        ))
        
        # Enter password
        Write-Host "🔑 Entering password"
        $passwordField.SendKeys($PASSWORD)
        
        # Submit
        Write-Host "🚪 Submitting login"
        $submitButton = $wait.Until([OpenQA.Selenium.Support.UI.ExpectedConditions]::ElementToBeClickable(
            [OpenQA.Selenium.By]::CssSelector("input[type='submit'][value='Sign in']")
        ))
        $submitButton.Click()
        
        # Check results
        Start-Sleep -Seconds 3
        Write-Host "📋 Checking login results"
        $failures = Check-FailureConditions -Driver $Driver
        
        return @{
            status = if ($failures.condition -contains "invalid_credentials") { "invalid_credentials" }
                    elseif ($failures.condition -contains "access_blocked") { "access_blocked" }
                    elseif ($failures.condition -contains "mfa_prompt") { "mfa_prompt" }
                    else { "success" }
            tested_url = $TestUrl.url
            service_name = $TestUrl.name
            details = $failures
        }
    }
    catch {
        Write-Host "❌ Error during login process: $_"
        Write-Host $_.ScriptStackTrace
        return @{
            status = "error"
            tested_url = $TestUrl.url
            service_name = $TestUrl.name
            message = $_.Exception.Message
        }
    }
}

function Send-TeamsWebhook {
    param(
        [array]$Results,
        [double]$ExecutionTime
    )
    
    if (-not $Results) { return }

    # Skip notifications for invalid credentials
    $filteredResults = $Results | Where-Object { $_.status -ne "invalid_credentials" }
    if (-not $filteredResults) {
        Write-Host "Skipping notification: Only invalid credentials detected"
        return
    }

    foreach ($result in $filteredResults) {
        $isAccessBlocked = $result.details.condition -contains "access_blocked"

        if ($isAccessBlocked) {
            $color = "00FF00"
            $title = "✅ Control Passed"
            $text = "Security control working: Access blocked successfully"
            $actualResult = "Access blocked"
        }
        else {
            $color = "FF0000"
            $title = "❌ Control Failed"
            $text = "Security control failed"
            $actualResult = "Login Successful since MFA prompt or other conditions met"
        }

        $payload = @{
            "@type" = "MessageCard"
            "@context" = "http://schema.org/extensions"
            "summary" = "Security Control Check"
            "themeColor" = $color
            "title" = $title
            "text" = "$text`n`n**Details:**`n- Execution Time: $($ExecutionTime.ToString('0.00'))s"
            "sections" = @(
                @{
                    "facts" = @(
                        @{ "name" = "Account:"; "value" = $EMAIL }
                        @{ "name" = "Tested URL:"; "value" = $result.tested_url }
                        @{ "name" = "Service Name:"; "value" = $result.service_name }
                        @{ "name" = "Result:"; "value" = $actualResult }
                    )
                }
            )
        }

        try {
            $jsonPayload = $payload | ConvertTo-Json -Depth 5
            Invoke-RestMethod -Uri $TEAMS_WEBHOOK_URL -Method Post -Body $jsonPayload -ContentType "application/json"
        }
        catch {
            Write-Host "Webhook error: $_"
        }
    }
}

# ----------------------
# Main Execution
# ----------------------

Write-Host "`n" + ("="*40)
Write-Host "🚀 Starting Security Control Test"
Write-Host "="*40

$driver = $null
$results = @()
$startTime = Get-Date

try {
    $driver = Initialize-Driver
    if (-not $driver) {
        Write-Host "❌ Aborting due to driver initialization failure"
        exit
    }

    foreach ($urlConfig in $TEST_URLS) {
        $result = Handle-Login -Driver $driver -TestUrl $urlConfig
        $results += $result
        Start-Sleep -Seconds 2
    }
}
catch [System.Management.Automation.KeyboardInterrupt] {
    Write-Host "`n🛑 Script interrupted by user"
}
catch {
    Write-Host "`n❌ Critical error: $_"
    Write-Host $_.ScriptStackTrace
}
finally {
    if ($driver) {
        Write-Host "`n🛑 Closing browser..."
        $driver.Quit()
    }

    $totalTime = (New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds
    Send-TeamsWebhook -Results $results -ExecutionTime $totalTime
}
