CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL DEFAULT '',
  grade TEXT NOT NULL DEFAULT 'First Secondary',
  school TEXT NOT NULL DEFAULT 'WE Luxor',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Students can read their own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
CREATE POLICY "Students can create their own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
CREATE POLICY "Students can update their own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

CREATE OR REPLACE FUNCTION public.handle_new_vyxia_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data ->> 'full_name', NEW.raw_user_meta_data ->> 'name', ''))
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;
CREATE TRIGGER on_auth_user_created_vyxia AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_vyxia_user();

CREATE TABLE public.lessons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_number SMALLINT NOT NULL,
  unit_title TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  page_start SMALLINT NOT NULL,
  page_end SMALLINT NOT NULL,
  sort_order SMALLINT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.lessons TO authenticated;
GRANT ALL ON public.lessons TO service_role;
ALTER TABLE public.lessons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Signed-in students can read lessons" ON public.lessons FOR SELECT TO authenticated USING (true);

CREATE TABLE public.threads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  lesson_id UUID REFERENCES public.lessons(id) ON DELETE SET NULL,
  title TEXT NOT NULL DEFAULT 'New conversation',
  model_id TEXT NOT NULL DEFAULT 'anthropic/claude-opus-5-5' CHECK (model_id IN ('openai/gpt-6-astra', 'anthropic/claude-opus-5-5', 'anthropic/claude-fable-5-1')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.threads TO authenticated;
GRANT ALL ON public.threads TO service_role;
ALTER TABLE public.threads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Students can read their conversations" ON public.threads FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Students can create their conversations" ON public.threads FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Students can update their conversations" ON public.threads FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Students can delete their conversations" ON public.threads FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE TABLE public.chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id UUID NOT NULL REFERENCES public.threads(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content TEXT NOT NULL DEFAULT '',
  parts JSONB NOT NULL DEFAULT '[]'::jsonb,
  ai_message_id TEXT,
  ai_model TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (thread_id, ai_message_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_messages TO authenticated;
GRANT ALL ON public.chat_messages TO service_role;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Students can read their messages" ON public.chat_messages FOR SELECT TO authenticated USING (auth.uid() = user_id AND EXISTS (SELECT 1 FROM public.threads t WHERE t.id = thread_id AND t.user_id = auth.uid()));
CREATE POLICY "Students can create their messages" ON public.chat_messages FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id AND EXISTS (SELECT 1 FROM public.threads t WHERE t.id = thread_id AND t.user_id = auth.uid()));
CREATE POLICY "Students can update their messages" ON public.chat_messages FOR UPDATE TO authenticated USING (auth.uid() = user_id AND EXISTS (SELECT 1 FROM public.threads t WHERE t.id = thread_id AND t.user_id = auth.uid())) WITH CHECK (auth.uid() = user_id AND EXISTS (SELECT 1 FROM public.threads t WHERE t.id = thread_id AND t.user_id = auth.uid()));
CREATE POLICY "Students can delete their messages" ON public.chat_messages FOR DELETE TO authenticated USING (auth.uid() = user_id AND EXISTS (SELECT 1 FROM public.threads t WHERE t.id = thread_id AND t.user_id = auth.uid()));
CREATE INDEX chat_messages_thread_created_idx ON public.chat_messages (thread_id, created_at);

CREATE TABLE public.quizzes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  lesson_id UUID REFERENCES public.lessons(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  questions JSONB NOT NULL DEFAULT '[]'::jsonb,
  answers JSONB NOT NULL DEFAULT '{}'::jsonb,
  score NUMERIC(6,2),
  status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed')),
  ai_model TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.quizzes TO authenticated;
GRANT ALL ON public.quizzes TO service_role;
ALTER TABLE public.quizzes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Students can read their quizzes" ON public.quizzes FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Students can create their quizzes" ON public.quizzes FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Students can update their quizzes" ON public.quizzes FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Students can delete their quizzes" ON public.quizzes FOR DELETE TO authenticated USING (auth.uid() = user_id);
CREATE INDEX quizzes_user_created_idx ON public.quizzes (user_id, created_at DESC);

CREATE TABLE public.chat_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id UUID NOT NULL REFERENCES public.threads(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  bucket_id TEXT NOT NULL CHECK (bucket_id IN ('vyxia-student-files', 'vyxia-generated-infographics')),
  object_path TEXT NOT NULL,
  filename TEXT NOT NULL,
  media_type TEXT NOT NULL,
  message_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (bucket_id, object_path)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_attachments TO authenticated;
GRANT ALL ON public.chat_attachments TO service_role;
ALTER TABLE public.chat_attachments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Students can read their attachment records" ON public.chat_attachments FOR SELECT TO authenticated USING (auth.uid() = user_id AND EXISTS (SELECT 1 FROM public.threads t WHERE t.id = thread_id AND t.user_id = auth.uid()));
CREATE POLICY "Students can create their attachment records" ON public.chat_attachments FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id AND EXISTS (SELECT 1 FROM public.threads t WHERE t.id = thread_id AND t.user_id = auth.uid()));
CREATE POLICY "Students can update their attachment records" ON public.chat_attachments FOR UPDATE TO authenticated USING (auth.uid() = user_id AND EXISTS (SELECT 1 FROM public.threads t WHERE t.id = thread_id AND t.user_id = auth.uid())) WITH CHECK (auth.uid() = user_id AND EXISTS (SELECT 1 FROM public.threads t WHERE t.id = thread_id AND t.user_id = auth.uid()));
CREATE POLICY "Students can delete their attachment records" ON public.chat_attachments FOR DELETE TO authenticated USING (auth.uid() = user_id AND EXISTS (SELECT 1 FROM public.threads t WHERE t.id = thread_id AND t.user_id = auth.uid()));
CREATE INDEX chat_attachments_thread_created_idx ON public.chat_attachments (thread_id, created_at);

CREATE POLICY "Students can access only their Vyxia student files" ON storage.objects FOR ALL TO authenticated USING (bucket_id = 'vyxia-student-files' AND (storage.foldername(name))[1] = auth.uid()::text) WITH CHECK (bucket_id = 'vyxia-student-files' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "Students can access only their Vyxia infographics" ON storage.objects FOR ALL TO authenticated USING (bucket_id = 'vyxia-generated-infographics' AND (storage.foldername(name))[1] = auth.uid()::text) WITH CHECK (bucket_id = 'vyxia-generated-infographics' AND (storage.foldername(name))[1] = auth.uid()::text);

INSERT INTO public.lessons (unit_number, unit_title, title, content, page_start, page_end, sort_order) VALUES
(1, 'Ratio and Similarity', 'Ratio, Proportion and Their Properties', '', 4, 8, 1),
(1, 'Ratio and Similarity', 'Direct Variation', '', 9, 12, 2),
(1, 'Ratio and Similarity', 'Inverse Variation', '', 13, 16, 3),
(1, 'Ratio and Similarity', 'Similarity of Polygons', '', 17, 24, 4),
(1, 'Ratio and Similarity', 'Similarity of Triangles', '', 25, 33, 5),
(2, 'Degree and Radian Measure', 'Directed Angle', '', 35, 41, 6),
(2, 'Degree and Radian Measure', 'Degree Measure and Radian Measure of an Angle', '', 42, 49, 7),
(2, 'Degree and Radian Measure', 'Circular Sector and Circular Segment', '', 50, 56, 8),
(3, 'Complex Numbers and Quadratic Equations', 'Complex Numbers', '', 60, 64, 9),
(3, 'Complex Numbers and Quadratic Equations', 'Addition and Subtraction of Complex Numbers', '', 65, 68, 10),
(3, 'Complex Numbers and Quadratic Equations', 'Multiplication of Complex Numbers and Conjugates', '', 69, 74, 11),
(3, 'Complex Numbers and Quadratic Equations', 'Types of Roots of a Quadratic Equation', '', 75, 78, 12);