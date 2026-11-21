import argparse
from getpass import getpass
from uuid import uuid4

from kapai.accounts import normalize_email, normalize_username, password_hasher
from kapai.db import execute, one
from kapai.runtime import engine


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["admin-create", "admin-revoke", "prune"])
    parser.add_argument("email", nargs="?")
    parser.add_argument("--username", help="Optional login username for admin-create")
    args = parser.parse_args()
    if args.action == "prune":
        with engine.begin() as db:
            execute(db, """
                DELETE FROM users WHERE activated_at IS NULL AND username IS NOT NULL
                AND created_at<UTC_TIMESTAMP()-INTERVAL 2 HOUR AND NOT EXISTS (
                    SELECT 1 FROM auth_tokens WHERE user_id=users.user_id AND kind='verify'
                    AND expires_at>UTC_TIMESTAMP()
                )
            """)
            execute(db, "DELETE FROM game_events WHERE received_at<UTC_TIMESTAMP()-INTERVAL 90 DAY")
            execute(db, "DELETE FROM save_receipts WHERE created_at<UTC_TIMESTAMP()-INTERVAL 30 DAY")
            execute(db, "DELETE FROM auth_tokens WHERE expires_at<UTC_TIMESTAMP()")
            execute(db, "DELETE FROM auth_sessions WHERE expires_at<UTC_TIMESTAMP()")
            execute(db, "DELETE FROM rate_limits WHERE window_start<UNIX_TIMESTAMP() DIV 900-1")
        return
    email = normalize_email(args.email or "")
    with engine.begin() as db:
        if args.action == "admin-create":
            username = normalize_username(args.username) if args.username else None
            password = getpass("New administrator password: ")
            if len(password) < 12 or len(password) > 128:
                raise SystemExit("Password must contain 12–128 characters")
            user = str(uuid4())
            execute(db, """
                INSERT INTO users (user_id,email,username,nickname,password_hash,role,verified_at,activated_at)
                VALUES (:user,:email,:username,'管理员',:password,'admin',UTC_TIMESTAMP(6),UTC_TIMESTAMP(6))
            """, user=user, email=email, username=username, password=password_hasher.hash(password))
        else:
            row = one(db, "SELECT user_id FROM users WHERE email=:email AND role='admin' FOR UPDATE", email=email)
            if not row:
                raise SystemExit("Administrator does not exist")
            user = row["user_id"]
            execute(db, "UPDATE users SET role='player',totp_secret=NULL,last_totp_step=NULL WHERE user_id=:user", user=user)
            execute(db, "DELETE FROM auth_sessions WHERE user_id=:user", user=user)
        execute(db, """
            INSERT INTO admin_audit_log (operation,object_id,result,request_id)
            VALUES (:action,:user,'ok',:request)
        """, action=args.action, user=user, request=str(uuid4()))
    if args.action == "admin-create":
        print("Administrator created. Sign in with the username or email and password.")


if __name__ == "__main__":
    main()
