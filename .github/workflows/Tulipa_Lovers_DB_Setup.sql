-- TULIPA LOVERS TAIF — isolated Supabase project only. Run in new empty project SQL Editor.
-- Deployment prerequisite: enable phone SMS provider + OTP in Supabase Auth; verify phone cost and abuse settings.
-- Prices / inventory in seed are placeholders; review before setting products active in real storefront.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE TABLE public.profiles (
 id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 full_name text NOT NULL DEFAULT 'عميل توليبا' CHECK (char_length(full_name) BETWEEN 2 AND 120),
 phone text,
 email text,
 role text NOT NULL DEFAULT 'customer' CHECK (role IN ('customer','owner')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.products (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 sku text NOT NULL UNIQUE,
 title_ar text NOT NULL CHECK (char_length(title_ar) BETWEEN 2 AND 160),
 description_ar text NOT NULL DEFAULT '',
 category text NOT NULL CHECK (category IN ('bouquets','gifts','natural','imported','occasions','wrapping')),
 kind text NOT NULL DEFAULT 'fixed' CHECK (kind IN ('fixed','custom')),
 price_sar numeric(12,2) NOT NULL DEFAULT 0 CHECK(price_sar>=0),
 stock_qty integer NOT NULL DEFAULT 0 CHECK(stock_qty>=0),
 image_path text NOT NULL DEFAULT 'bouquet_rose.jpg',
 active boolean NOT NULL DEFAULT false,
 featured boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.orders (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 request_id uuid NOT NULL,
 customer_id uuid NOT NULL REFERENCES auth.users(id),
 recipient_name text NOT NULL CHECK(char_length(recipient_name) BETWEEN 2 AND 120),
 recipient_phone text NOT NULL CHECK(recipient_phone ~ '^\+9665[0-9]{8}$'),
 city text NOT NULL DEFAULT 'الطائف' CHECK(city='الطائف'),
 district text NOT NULL CHECK(char_length(district) BETWEEN 2 AND 120),
 address_text text NOT NULL CHECK(char_length(address_text) BETWEEN 5 AND 300),
 delivery_at timestamptz NOT NULL,
 customer_note text NOT NULL DEFAULT '' CHECK(char_length(customer_note) <= 500),
 subtotal_sar numeric(12,2) NOT NULL DEFAULT 0 CHECK(subtotal_sar >= 0),
 delivery_sar numeric(12,2) NOT NULL DEFAULT 30 CHECK(delivery_sar >= 0),
 discount_sar numeric(12,2) NOT NULL DEFAULT 0 CHECK(discount_sar >= 0),
 total_sar numeric(12,2) NOT NULL DEFAULT 0 CHECK(total_sar >= 0),
 redeemed_points integer NOT NULL DEFAULT 0 CHECK(redeemed_points >= 0),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','pending_review','confirmed','preparing','out_for_delivery','delivered','cancelled')),
 payment_method text NOT NULL DEFAULT 'cash_on_delivery' CHECK(payment_method='cash_on_delivery'),
 payment_status text NOT NULL DEFAULT 'unpaid' CHECK(payment_status IN ('unpaid','paid')),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(customer_id, request_id)
);
CREATE INDEX ix_orders_customer ON public.orders(customer_id, created_at DESC);
CREATE TABLE public.order_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
 product_id uuid NOT NULL REFERENCES public.products(id),
 product_title text NOT NULL,
 quantity integer NOT NULL CHECK(quantity BETWEEN 1 AND 10),
 unit_price_sar numeric(12,2) NOT NULL CHECK(unit_price_sar>=0),
 customization jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE TABLE public.loyalty_ledger (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES auth.users(id),
 order_id uuid NOT NULL REFERENCES public.orders(id),
 points_delta integer NOT NULL CHECK(points_delta<>0),
 reason text NOT NULL CHECK(reason IN ('redeemed','earned','refund_redeemed','reverse_earned')),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(order_id, reason)
);
CREATE INDEX ix_loyalty_user ON public.loyalty_ledger(user_id,created_at DESC);
CREATE TABLE public.event_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 customer_id uuid NOT NULL REFERENCES auth.users(id),
 event_type text NOT NULL CHECK(char_length(event_type) BETWEEN 2 AND 80),
 event_date date NOT NULL,
 district text NOT NULL CHECK(char_length(district) BETWEEN 2 AND 120),
 budget_sar numeric(12,2) CHECK(budget_sar >= 0),
 details text NOT NULL CHECK(char_length(details) BETWEEN 10 AND 1000),
 status text NOT NULL DEFAULT 'new' CHECK(status IN ('new','contacted','quoted','approved','closed')),
 created_at timestamptz NOT NULL DEFAULT now()
);

-- Create a customer record when Supabase creates a verified (or pending verification) auth account.
CREATE FUNCTION private.create_profile() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 INSERT INTO public.profiles(id,full_name,phone,email)
 VALUES(new.id, coalesce(nullif(left(new.raw_user_meta_data->>'full_name',120),''),'عميل توليبا'), new.phone, new.email)
 ON CONFLICT(id) DO NOTHING;
 RETURN new;
END; $$;
CREATE TRIGGER trg_new_auth_user AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION private.create_profile();
CREATE FUNCTION private.sync_contact() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 UPDATE public.profiles SET phone=new.phone, email=new.email WHERE id=new.id;
 RETURN new;
END; $$;
CREATE TRIGGER trg_auth_contact AFTER UPDATE OF phone,email ON auth.users
FOR EACH ROW WHEN (old.phone IS DISTINCT FROM new.phone OR old.email IS DISTINCT FROM new.email)
EXECUTE FUNCTION private.sync_contact();

CREATE FUNCTION private.is_owner() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id=(SELECT auth.uid()) AND role='owner');
$$;
REVOKE ALL ON FUNCTION private.is_owner() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_owner() TO authenticated;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_requests ENABLE ROW LEVEL SECURITY;

-- Roles / grants are part of the firewall, not just RLS.
REVOKE ALL ON public.profiles,public.products,public.orders,public.order_items,public.loyalty_ledger,public.event_requests FROM anon, authenticated;
GRANT SELECT ON public.products TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.products TO authenticated;
GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE(full_name) ON public.profiles TO authenticated;
GRANT SELECT ON public.orders,public.order_items,public.loyalty_ledger TO authenticated;
GRANT UPDATE(status,payment_status) ON public.orders TO authenticated;
GRANT SELECT, INSERT ON public.event_requests TO authenticated;
GRANT UPDATE(status) ON public.event_requests TO authenticated;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

CREATE POLICY product_public_read ON public.products FOR SELECT TO anon,authenticated USING (active);
CREATE POLICY product_owner_read ON public.products FOR SELECT TO authenticated USING ((SELECT private.is_owner()));
CREATE POLICY product_owner_insert ON public.products FOR INSERT TO authenticated WITH CHECK ((SELECT private.is_owner()));
CREATE POLICY product_owner_update ON public.products FOR UPDATE TO authenticated USING ((SELECT private.is_owner())) WITH CHECK ((SELECT private.is_owner()));
CREATE POLICY product_owner_delete ON public.products FOR DELETE TO authenticated USING ((SELECT private.is_owner()));
CREATE POLICY profile_read ON public.profiles FOR SELECT TO authenticated USING (id=(SELECT auth.uid()) OR (SELECT private.is_owner()));
CREATE POLICY profile_update_self ON public.profiles FOR UPDATE TO authenticated USING (id=(SELECT auth.uid())) WITH CHECK (id=(SELECT auth.uid()));
CREATE POLICY orders_read ON public.orders FOR SELECT TO authenticated USING(customer_id=(SELECT auth.uid()) OR (SELECT private.is_owner()));
CREATE POLICY orders_owner_update ON public.orders FOR UPDATE TO authenticated USING((SELECT private.is_owner())) WITH CHECK((SELECT private.is_owner()));
CREATE POLICY order_items_read ON public.order_items FOR SELECT TO authenticated USING(
 (SELECT private.is_owner()) OR EXISTS (SELECT 1 FROM public.orders o WHERE o.id=order_id AND o.customer_id=(SELECT auth.uid()))
);
CREATE POLICY loyalty_read ON public.loyalty_ledger FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid()) OR (SELECT private.is_owner()));
CREATE POLICY events_insert ON public.event_requests FOR INSERT TO authenticated WITH CHECK(customer_id=(SELECT auth.uid()));
CREATE POLICY events_read ON public.event_requests FOR SELECT TO authenticated USING(customer_id=(SELECT auth.uid()) OR (SELECT private.is_owner()));
CREATE POLICY events_owner_update ON public.event_requests FOR UPDATE TO authenticated USING((SELECT private.is_owner())) WITH CHECK((SELECT private.is_owner()));

-- Creates an order atomically; client-supplied pricing is never trusted.
CREATE FUNCTION private.place_order(
 p_request_id uuid, p_items jsonb, p_recipient_name text, p_recipient_phone text,
 p_district text, p_address text, p_delivery_at timestamptz,
 p_customer_note text DEFAULT '', p_redeem_points integer DEFAULT 0
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
 v_user uuid := auth.uid(); v_order uuid; v_existing uuid;
 v_line jsonb; v_product public.products%ROWTYPE; v_qty int; v_price numeric(12,2);
 v_subtotal numeric(12,2):=0; v_delivery numeric(12,2):=30; v_discount numeric(12,2):=0;
 v_custom jsonb; v_flower text; v_wrap text; v_stems int; v_card boolean;
 v_review boolean:=false; v_points integer:=0; v_total_items int:=0;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Login required'; END IF;
 IF p_request_id IS NULL THEN RAISE EXCEPTION 'Missing request ID'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_user::text)::bigint);
 SELECT id INTO v_existing FROM public.orders WHERE customer_id=v_user AND request_id=p_request_id;
 IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;
 IF p_items IS NULL OR pg_catalog.jsonb_typeof(p_items) <> 'array' OR pg_catalog.jsonb_array_length(p_items) NOT BETWEEN 1 AND 20 THEN
  RAISE EXCEPTION 'Choose 1–20 items';
 END IF;
 IF pg_catalog.char_length(pg_catalog.btrim(coalesce(p_recipient_name,''))) NOT BETWEEN 2 AND 120
    OR coalesce(p_recipient_phone,'') !~ '^\+9665[0-9]{8}$'
    OR pg_catalog.char_length(pg_catalog.btrim(coalesce(p_district,''))) NOT BETWEEN 2 AND 120
    OR pg_catalog.char_length(pg_catalog.btrim(coalesce(p_address,''))) NOT BETWEEN 5 AND 300
    OR pg_catalog.char_length(coalesce(p_customer_note,'')) > 500 THEN RAISE EXCEPTION 'Invalid delivery information'; END IF;
 IF p_delivery_at IS NULL OR p_delivery_at < now()+ interval '2 hours' OR p_delivery_at > now()+ interval '60 days' THEN
  RAISE EXCEPTION 'Delivery slot outside allowed window'; END IF;
 IF p_redeem_points IS NULL OR p_redeem_points < 0 OR mod(p_redeem_points,100)<>0 THEN
  RAISE EXCEPTION 'Loyalty redemption requires 100-point increments'; END IF;
 INSERT INTO public.orders(request_id,customer_id,recipient_name,recipient_phone,district,address_text,delivery_at,customer_note)
 VALUES(p_request_id,v_user,pg_catalog.btrim(p_recipient_name),p_recipient_phone,pg_catalog.btrim(p_district),pg_catalog.btrim(p_address),p_delivery_at,coalesce(p_customer_note,''))
 RETURNING id INTO v_order;
 FOR v_line IN SELECT value FROM pg_catalog.jsonb_array_elements(p_items) LOOP
  IF pg_catalog.jsonb_typeof(v_line) <> 'object' OR v_line->>'product_id' IS NULL THEN RAISE EXCEPTION 'Invalid cart item'; END IF;
  v_qty := (v_line->>'quantity')::int;
  IF v_qty NOT BETWEEN 1 AND 10 THEN RAISE EXCEPTION 'Invalid quantity'; END IF;
  v_total_items:=v_total_items+v_qty;
  IF v_total_items > 50 THEN RAISE EXCEPTION 'Maximum 50 pieces per order'; END IF;
  SELECT * INTO v_product FROM public.products WHERE id=(v_line->>'product_id')::uuid AND active=true FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product unavailable'; END IF;
  v_custom := coalesce(v_line->'customization','{}'::jsonb);
  IF pg_catalog.jsonb_typeof(v_custom)<>'object' THEN RAISE EXCEPTION 'Invalid options'; END IF;
  IF v_product.kind='custom' THEN
   v_flower:=v_custom->>'flower'; v_wrap:=v_custom->>'wrap'; v_stems:=(v_custom->>'stems')::int;
   v_card:=coalesce((v_custom->>'card')::boolean,false);
   IF v_flower NOT IN ('rose','tulip','lily') OR v_wrap NOT IN ('classic','luxury','box')
      OR v_stems NOT IN (10,15,25,50) THEN RAISE EXCEPTION 'Unsupported bouquet configuration'; END IF;
   v_custom:=pg_catalog.jsonb_build_object('flower',v_flower,'wrap',v_wrap,'stems',v_stems,'card',v_card);
   v_price:=v_stems * (CASE v_flower WHEN 'rose' THEN 12 WHEN 'tulip' THEN 17 ELSE 22 END)
    + (CASE v_wrap WHEN 'classic' THEN 15 WHEN 'luxury' THEN 30 ELSE 45 END)
    + (CASE WHEN v_card THEN 10 ELSE 0 END);
   v_review:=true; -- Flower-component stock checked by florist before accepting custom work.
  ELSE
   IF v_custom <> '{}'::jsonb THEN RAISE EXCEPTION 'Fixed bouquet cannot accept custom pricing'; END IF;
   IF v_product.stock_qty < v_qty THEN RAISE EXCEPTION 'Not enough stock: %', v_product.title_ar; END IF;
   UPDATE public.products SET stock_qty=stock_qty-v_qty WHERE id=v_product.id;
   v_price:=v_product.price_sar;
  END IF;
  INSERT INTO public.order_items(order_id,product_id,product_title,quantity,unit_price_sar,customization)
  VALUES(v_order,v_product.id,v_product.title_ar,v_qty,v_price,v_custom);
  v_subtotal:=v_subtotal+v_price*v_qty;
 END LOOP;
 IF p_redeem_points>0 THEN
  SELECT coalesce(sum(points_delta),0) INTO v_points FROM public.loyalty_ledger WHERE user_id=v_user;
  IF v_points < p_redeem_points THEN RAISE EXCEPTION 'Insufficient loyalty points'; END IF;
  v_discount:=p_redeem_points / 20.0;
  IF v_discount > v_subtotal * 0.20 THEN RAISE EXCEPTION 'Loyalty discount exceeds 20 percent'; END IF;
  INSERT INTO public.loyalty_ledger(user_id,order_id,points_delta,reason)
  VALUES(v_user,v_order,-p_redeem_points,'redeemed');
 END IF;
 UPDATE public.orders SET subtotal_sar=v_subtotal,delivery_sar=v_delivery,discount_sar=v_discount,
 total_sar=v_subtotal+v_delivery-v_discount,redeemed_points=p_redeem_points,
 status=(CASE WHEN v_review THEN 'pending_review' ELSE 'pending' END)
 WHERE id=v_order;
 RETURN v_order;
END; $$;
REVOKE ALL ON FUNCTION private.place_order(uuid,jsonb,text,text,text,text,timestamptz,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.place_order(uuid,jsonb,text,text,text,text,timestamptz,text,integer) TO authenticated;
CREATE FUNCTION public.submit_order(
 p_request_id uuid, p_items jsonb, p_recipient_name text, p_recipient_phone text,
 p_district text, p_address text, p_delivery_at timestamptz,
 p_customer_note text DEFAULT '', p_redeem_points integer DEFAULT 0
) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
 SELECT private.place_order(p_request_id,p_items,p_recipient_name,p_recipient_phone,p_district,p_address,p_delivery_at,p_customer_note,p_redeem_points);
$$;
REVOKE ALL ON FUNCTION public.submit_order(uuid,jsonb,text,text,text,text,timestamptz,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_order(uuid,jsonb,text,text,text,text,timestamptz,text,integer) TO authenticated;

-- Award points only after the OWNER marks an order PAID and DELIVERED.
CREATE FUNCTION private.after_order_update() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF new.status='delivered' AND new.payment_status='paid' AND (old.status IS DISTINCT FROM new.status OR old.payment_status IS DISTINCT FROM new.payment_status) THEN
  INSERT INTO public.loyalty_ledger(user_id,order_id,points_delta,reason)
  VALUES(new.customer_id,new.id,greatest(1,pg_catalog.floor(new.subtotal_sar-new.discount_sar)::integer),'earned')
  ON CONFLICT(order_id,reason) DO NOTHING;
 END IF;
 IF old.status='delivered' AND new.status <> 'delivered' THEN RAISE EXCEPTION 'Delivered orders are terminal'; END IF;
 IF old.status='cancelled' AND new.status <> 'cancelled' THEN RAISE EXCEPTION 'Cancelled orders cannot be reopened'; END IF;
 IF new.status='cancelled' AND old.status <> 'cancelled' THEN
  IF new.payment_status='paid' THEN RAISE EXCEPTION 'Refund payment before cancellation'; END IF;
  IF old.status='delivered' THEN RAISE EXCEPTION 'Delivered orders cannot be cancelled'; END IF;
  -- Return stock allocated to fixed-price lines.
  UPDATE public.products p SET stock_qty=p.stock_qty+x.qty
  FROM (SELECT i.product_id, sum(i.quantity)::integer AS qty FROM public.order_items i
        WHERE i.order_id=new.id AND i.customization='{}'::jsonb GROUP BY i.product_id) x
  WHERE p.id=x.product_id;
  IF new.redeemed_points>0 THEN
   INSERT INTO public.loyalty_ledger(user_id,order_id,points_delta,reason)
   VALUES(new.customer_id,new.id,new.redeemed_points,'refund_redeemed')
   ON CONFLICT(order_id,reason) DO NOTHING;
  END IF;
 END IF;
 RETURN new;
END; $$;
CREATE TRIGGER trg_after_order_update AFTER UPDATE OF status,payment_status ON public.orders
FOR EACH ROW EXECUTE FUNCTION private.after_order_update();

-- Optional catalog preview. All examples start INACTIVE to prevent accidental real orders before owner approval.
INSERT INTO public.products(id,sku,title_ar,description_ar,category,kind,price_sar,stock_qty,image_path,active,featured) VALUES
('4a2cdaf0-5ee4-49cc-a99f-000000000001','TL-001','بوكيه توليبا كلاسيك','توليب أبيض مع تغليف أزرق رمادي أنيق','bouquets','fixed',249,0,'bouquet_white.jpg',false,true),
('4a2cdaf0-5ee4-49cc-a99f-000000000002','TL-002','بوكيه لمسة ورد','تشكيلة وردية ناعمة للمناسبات','bouquets','fixed',299,0,'bouquet_pink.jpg',false,true),
('4a2cdaf0-5ee4-49cc-a99f-000000000003','TL-003','تنسيق الفخامة البيضاء','ورود بيضاء داخل صندوق أنيق','gifts','fixed',349,0,'bouquet_box.jpg',false,false),
('4a2cdaf0-5ee4-49cc-a99f-000000000004','TL-004','باقة توليبا وهدية','تنسيق هدايا باللون الوردي','gifts','fixed',329,0,'bouquet_gift.jpg',false,false),
('4a2cdaf0-5ee4-49cc-a99f-000000000005','TL-CUSTOM','صمّم بوكيهك','تصميم خاص وسعر تقديري يعتمد التنفيذ على تأكيد المحل','bouquets','custom',0,0,'hero_bouquet.jpg',false,true);
COMMIT;
-- Bootstrap OWNER after first successful OTP signup (SQL Editor with privileged account):
-- UPDATE public.profiles SET role='owner' WHERE id='YOUR_AUTH_USER_UUID';
-- Never allow customers to change role. Never put SUPABASE_SECRET/SERVICE_ROLE key in site or GitHub.
