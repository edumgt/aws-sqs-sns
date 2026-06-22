"""SES 이메일 발송 서비스"""
import boto3

client = boto3.client('ses', region_name='ap-northeast-2')


def send_email(from_email: str, to_email: str, subject: str, message: str) -> None:
    client.send_email(
        Source=from_email,
        Destination={'ToAddresses': [to_email]},
        Message={
            'Subject': {'Data': subject, 'Charset': 'UTF-8'},
            'Body': {'Text': {'Data': message, 'Charset': 'UTF-8'}},
        },
    )
