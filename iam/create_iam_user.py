import boto3
import csv
import secrets
import string


def generate_password(length=12):
    """Generate a secure random password."""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()-_=+"
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def create_iam_user(email):
    iam = boto3.client('iam')

    # Use the email prefix as username (remove domain and special chars if needed)
    username = email.split('@')[0]

    try:
        # Create IAM user
        iam.create_user(UserName=username)
        print(f"Created user: {username}")

        # Generate initial password
        initial_password = generate_password()

        # Create login profile with password, require password reset on first login
        iam.create_login_profile(
            UserName=username,
            Password=initial_password,
            PasswordResetRequired=True
        )
        print("Login profile created with initial password.")

        # Create access keys
        access_key_response = iam.create_access_key(UserName=username)
        access_key_id = access_key_response['AccessKey']['AccessKeyId']
        secret_access_key = access_key_response['AccessKey']['SecretAccessKey']
        print("Access keys created.")

        # Prepare CSV data
        csv_data = [
            ['UserName', 'Email', 'InitialPassword', 'AccessKeyId', 'SecretAccessKey'],
            [username, email, initial_password, access_key_id, secret_access_key]
        ]

        # Write to CSV file
        csv_filename = f"{username}_credentials.csv"
        with open(csv_filename, mode='w', newline='') as file:
            writer = csv.writer(file)
            writer.writerows(csv_data)

        print(f"Credentials saved to {csv_filename}")

    except Exception as e:
        print(f"Error creating user: {e}")

if __name__ == "__main__":
    email_input = input("Enter the email address for the new IAM user: ")
    create_iam_user(email_input)
