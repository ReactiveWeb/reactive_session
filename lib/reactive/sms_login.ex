defmodule Reactive.SmsLogin do
  require Logger

  def send_sms(to,text) do
    url =  Application.get_env(:reactive_session, :sms_url)
    msg = %{
      dst: to,
      text: text,
      src: Application.get_env(:reactive_session, :sms_src)
    }
    auth="Basic " <> :base64.encode(Application.get_env(:reactive_session, :sms_auth_id) <>
      ":" <> Application.get_env(:reactive_session, :sms_auth_token))

    headers = [
      {"Content-Type","application/json"},
      {"Authorization",auth}
    ]

    case HTTPoison.post(url, :jsx.encode(msg),headers) do
      {:error, err} -> {:error, err}
      {:ok, resp} ->
        case resp do
          %HTTPoison.Response{status_code: 202, body: respJson} ->
            Logger.debug("SMS RESULT #{inspect respJson}")
            :ok
          %HTTPoison.Response{status_code: code}  ->
            Logger.debug("SMS ERROR #{inspect resp}")
            {:error, code}
        end
    end
  end

  def generate_user_id() do
    << a :: size(32), b :: size(32), c :: size(32), d :: size(32)  >> = :crypto.strong_rand_bytes(16)
    :erlang.integer_to_binary(a,16) <> "_" <> :erlang.integer_to_binary(b,16) <> "_" <>
      :erlang.integer_to_binary(c,16) <> "_" <> :erlang.integer_to_binary(d,16)
  end

  def api_request(:sms_send,[_,sessionId],_contexts,phone) do
    existingUsers = Reactive.EntitiesIndexDb.find({Reactive.Entities.get_db(),"user_phone"},phone)
    case existingUsers do
      [] ->
        << rint :: size(24) >> = :crypto.strong_rand_bytes(3)
        code = :erlang.list_to_binary(:erlang.integer_to_list(rem(rint,10000)))

        user_id = generate_user_id()
        user = [Reactive.User,user_id]
        Reactive.User.set(user,:phone,phone)
        Reactive.User.set(user,:phone_confirmed,false)
        Reactive.User.set(user,:phone_code,code)

        ## TODO: phone code expiry

        Reactive.User.set_ident(user,:phone,phone)

        send_sms(phone,Application.get_env(:reactive_session, :sms_code_msg)<>code)

        :created
      [user] ->
        ucode = Reactive.User.get(user,:phone_code)
        code = if(ucode == :undefined) do
          << rint :: size(24) >> = :crypto.strong_rand_bytes(3)
          code = :erlang.list_to_binary(:erlang.integer_to_list(rem(rint,100000)))
          Reactive.User.set(user,:phone_code,code)
          code
        else
          ucode
        end

        send_sms(phone,Application.get_env(:reactive_session, :sms_code_msg)<>code)

        :exists
    end
  end

  def api_request(:sms_login,[_,sessionId],_contexts,phone,code) do
    case Reactive.EntitiesIndexDb.find({Reactive.Entities.get_db(),"user_phone"},phone) do
      [user]=[[Reactive.User,userId]] ->
        ucode = Reactive.User.get(user,:phone_code)
        if(ucode == code) do
          Reactive.User.unset(user,:phone_code)
          session=[Reactive.Session,sessionId]
          Reactive.User.set(user,:phone_confirmed,true)
          Reactive.Entity.request(session,{:login,userId})
          :ok
        else
          :unknown_credentials
        end
      _ -> :unknown_credentials
    end
  end
end