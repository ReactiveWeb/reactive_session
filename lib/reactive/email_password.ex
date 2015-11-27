defmodule Reactive.EmailPassword do
  require Logger
  use Mailgun.Client, domain: Application.get_env(:reactive_session, :mailgun_domain),
                      key: Application.get_env(:reactive_session, :mailgun_key)

  def password_hash(password) do
    :crypto.hash(:sha224,"salt23"<>password<>"|||") |> Base.encode16
  end

  def api_request(:create,[_,sessionId],_contexts,uemail,password,data) do
    email=String.downcase(uemail)
    existingUsers=Reactive.EntitiesIndexDb.find({Reactive.Entities.get_db(),"user_email"},email)
    case existingUsers do
      [] ->
        code = :base64.encode(:crypto.strong_rand_bytes(18))

        user=[Reactive.User,email]
        Reactive.User.set(user,:email,email)
        Reactive.User.set(user,:email_confirmed,false)
        Reactive.User.set(user,:info,data)
        Reactive.User.set(user,:password_hash,password_hash(password))
        Reactive.User.set_ident(user,:email,email)
        Reactive.User.set_ident(user,:email_confirm_code,code)

        link = Application.get_env(:reactive_session, :email_password_url_confirm_email) <> code

        res=send_email to: email,
                       from:  Application.get_env(:reactive_session, :email_sender),
                       subject: "Confirm account email",
                       text: "Confirm your email: "<>link
        Logger.info("Email result #{inspect res}")

        :created
      _ ->
        :exists
    end
  end

  def api_request(:send_confirm_link,[_,_sessionId],_contexts,email) do
    [user]=Reactive.EntitiesIndexDb.find({Reactive.Entities.get_db(),"user_email"},email)
    code = :base64.encode(:crypto.strong_rand_bytes(18))
    Reactive.User.set_ident(user,:email_confirm_code,code)
    link = Application.get_env(:reactive_session, :email_password_url_confirm_email) <> code

    res=send_email to: email,
                   from:  Application.get_env(:reactive_session, :email_sender),
                   subject: "Confirm account email",
                   text: "Confirm your email: "<>link

    Logger.info("Email result #{inspect res}")
    :ok
  end

  def api_request(:confirm_email,[_,sessionId],_contexts,code) do
    case Reactive.EntitiesIndexDb.find({Reactive.Entities.get_db(),"user_email_confirm_code"},code) do
      [user]=[[Reactive.User,userId]] ->
        Reactive.User.delete_ident(user,:email_confirm_code)
        Reactive.User.set(user,:email_confirmed,true)
        session=[Reactive.Session,sessionId]
        #Logger.debug("Login session #{inspect session}")
        Reactive.Entity.request(session,{:login,userId})
        :ok
      _ ->
        :not_found
    end
  end

  def api_request(:send_reset_link,[_,sessionId],_contexts,email) do
    case Reactive.EntitiesIndexDb.find({Reactive.Entities.get_db(),"user_email"},email) do
      [user] ->
        code = :base64.encode(:crypto.strong_rand_bytes(18))
        Reactive.User.set_ident(user,:reset_password_code,code)
        link = Application.get_env(:reactive_session, :email_password_url_reset_password) <> code

        send_email to: email,
                   from:  Application.get_env(:reactive_session, :email_sender),
                   subject: "Reset password email",
                   text: "To reset your password click: "<>link
        :ok
      _ ->
        :not_found
    end
  end

  def api_request(:check_reset_code,[_,sessionId],_contexts,code) do
    case Reactive.EntitiesIndexDb.find({Reactive.Entities.get_db(),"user_reset_password_code"},code) do
      [user] ->
        Reactive.User.set(user,:email_confirmed,true)
        :ok
      _ ->
        :not_found
    end
  end

  def api_request(:reset_password,[_,sessionId],_contexts,code,password) do
    case Reactive.EntitiesIndexDb.find({Reactive.Entities.get_db(),"user_reset_password_code"},code) do
      [user]=[[Reactive.User,userId]] ->
        Reactive.User.delete_ident(user,:reset_password_code)
        Reactive.User.set(user,:email_confirmed,true)
        Reactive.User.set(user,:password_hash,password_hash(password))

        session=[Reactive.Session,sessionId]
        Reactive.Entity.request(session,{:login,userId})
        :ok
      _ ->
        :not_found
    end
  end

  def api_request(:change_password,[_,sessionId],_contexts,password) do
    session=[Reactive.Session,sessionId]
    case Reactive.Entity.get(session,:login_status) do
      user=[Reactive.User | _] ->
        Reactive.User.set(user,:password_hash,password_hash(password))
      _ -> :not_logged_in
    end
  end

  def api_request(:login,[_,sessionId],_contexts,email,password) do
    case Reactive.EntitiesIndexDb.find({Reactive.Entities.get_db(),"user_email"},email) do
      [user]=[[Reactive.User,userId]] ->
        user_ph = Reactive.User.get(user,:password_hash)
        if(user_ph == password_hash(password)) do
        session=[Reactive.Session,sessionId]
          if(Reactive.User.get(user,:email_confirmed)) do
            Reactive.Entity.request(session,{:login,userId})
            :ok
          else
            :not_confirmed
          end
        else
          :unknown_credentials
        end
      _ -> :unknown_credentials
    end
  end

end