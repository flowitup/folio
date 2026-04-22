import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import sys


def send_test_email():
    # Configuration
    SMTP_HOST = "smtp.resend.com"
    SMTP_PORT = 587
    SMTP_USER = "resend"
    SMTP_PASS = "re_QhMnP4zk_3CyxkgAyMwnHzVE8nSwrWp9c"

    SENDER_EMAIL = "system@flowitup.com"  # Using your verified domain
    RECIPIENT_EMAIL = "trungbuiforgame@gmail.com"  # Using the address authorized by your Resend account

    print(f"--- Attempting to send test email via {SMTP_HOST} ---")

    # Create Message
    message = MIMEMultipart()
    message["From"] = SENDER_EMAIL
    message["To"] = RECIPIENT_EMAIL
    message["Subject"] = "🚀 Resend SMTP Test - FlowItUp"

    body = """
    Hello!
    
    This is a test email sent from your Construction Management System 
    using Resend SMTP with your flowitup.com domain configuration.
    
    If you received this, your SMTP setup is working perfectly!
    """
    message.attach(MIMEText(body, "plain"))

    try:
        # Connect to server
        print(f"Connecting to {SMTP_HOST}:{SMTP_PORT}...")
        server = smtplib.SMTP(SMTP_HOST, SMTP_PORT)
        server.set_debuglevel(1)  # Show the SMTP conversation

        print("Starting TLS...")
        server.starttls()

        print("Logging in...")
        server.login(SMTP_USER, SMTP_PASS)

        print(f"Sending email to {RECIPIENT_EMAIL}...")
        server.send_message(message)

        print("✅ Success! Email sent.")
        server.quit()

    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    send_test_email()
