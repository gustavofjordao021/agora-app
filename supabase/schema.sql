-- FoodNoms Clone Database Schema
-- Run this in Supabase SQL Editor

-- ============================================
-- EXTENSIONS
-- ============================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- TABLES
-- ============================================

-- User Profiles (extends Supabase auth.users)
CREATE TABLE user_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE NOT NULL,

  display_name VARCHAR(100),
  email VARCHAR(255),

  -- Preferences
  default_meal_type VARCHAR(20) DEFAULT 'snack' CHECK (default_meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
  use_metric BOOLEAN DEFAULT TRUE,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- User Nutrition Goals
CREATE TABLE user_goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE NOT NULL,

  -- Daily targets
  calories_target INTEGER CHECK (calories_target > 0),
  protein_target INTEGER CHECK (protein_target >= 0),      -- grams
  carbs_target INTEGER CHECK (carbs_target >= 0),          -- grams
  fat_target INTEGER CHECK (fat_target >= 0),              -- grams
  fiber_target INTEGER CHECK (fiber_target >= 0),          -- grams
  sugar_limit INTEGER CHECK (sugar_limit >= 0),            -- grams (upper limit)
  sodium_limit INTEGER CHECK (sodium_limit >= 0),          -- mg (upper limit)
  water_target INTEGER CHECK (water_target >= 0),          -- ml

  -- Goal type for suggestions
  goal_type VARCHAR(50) DEFAULT 'maintain' CHECK (goal_type IN ('lose_weight', 'maintain', 'gain_muscle', 'custom')),

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Foods Database (user-contributed + cached from external sources)
CREATE TABLE foods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,

  -- Identification
  barcode VARCHAR(50),
  name VARCHAR(255) NOT NULL,
  brand VARCHAR(255),
  description TEXT,

  -- Primary serving info
  serving_size DECIMAL(10,2) NOT NULL CHECK (serving_size > 0),
  serving_unit VARCHAR(50) NOT NULL, -- 'g', 'ml', 'oz', 'cup', 'piece', etc.
  serving_description VARCHAR(100), -- e.g., "1 medium apple (182g)"

  -- Nutrition per serving
  calories DECIMAL(10,2) CHECK (calories >= 0),
  protein DECIMAL(10,2) CHECK (protein >= 0),
  carbohydrates DECIMAL(10,2) CHECK (carbohydrates >= 0),
  fat DECIMAL(10,2) CHECK (fat >= 0),
  fiber DECIMAL(10,2) CHECK (fiber >= 0),
  sugar DECIMAL(10,2) CHECK (sugar >= 0),
  sodium DECIMAL(10,2) CHECK (sodium >= 0),           -- mg
  saturated_fat DECIMAL(10,2) CHECK (saturated_fat >= 0),
  trans_fat DECIMAL(10,2) CHECK (trans_fat >= 0),
  cholesterol DECIMAL(10,2) CHECK (cholesterol >= 0), -- mg
  potassium DECIMAL(10,2) CHECK (potassium >= 0),     -- mg

  -- Metadata
  verified BOOLEAN DEFAULT FALSE,
  source VARCHAR(50) DEFAULT 'user' CHECK (source IN ('user', 'usda', 'openfoodfacts', 'ai')),
  external_id VARCHAR(100), -- ID from external source (USDA fdcId, OFF code)
  image_url TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create unique index on barcode (allowing NULL)
CREATE UNIQUE INDEX idx_foods_barcode ON foods(barcode) WHERE barcode IS NOT NULL;

-- Food text search index
CREATE INDEX idx_foods_name_search ON foods USING gin(to_tsvector('english', name || ' ' || COALESCE(brand, '')));

-- Alternative Serving Sizes
CREATE TABLE food_servings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  food_id UUID REFERENCES foods(id) ON DELETE CASCADE NOT NULL,

  name VARCHAR(100) NOT NULL,            -- '1 cup', '1 slice', '1 large'
  amount DECIMAL(10,2) NOT NULL,         -- numeric amount
  unit VARCHAR(50) NOT NULL,             -- 'cup', 'slice', 'piece', 'g', 'oz'
  gram_equivalent DECIMAL(10,2),         -- grams equivalent for conversion

  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_food_servings_food ON food_servings(food_id);

-- Food Log Entries
CREATE TABLE food_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  food_id UUID REFERENCES foods(id) ON DELETE SET NULL,

  -- When and what meal
  log_date DATE NOT NULL,
  meal_type VARCHAR(20) NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
  logged_at TIMESTAMPTZ DEFAULT NOW(), -- Exact time logged

  -- Portion info
  servings DECIMAL(10,3) NOT NULL DEFAULT 1 CHECK (servings > 0),
  serving_id UUID REFERENCES food_servings(id) ON DELETE SET NULL,

  -- Calculated nutrition at log time (denormalized for historical accuracy)
  calories DECIMAL(10,2),
  protein DECIMAL(10,2),
  carbohydrates DECIMAL(10,2),
  fat DECIMAL(10,2),
  fiber DECIMAL(10,2),
  sugar DECIMAL(10,2),
  sodium DECIMAL(10,2),

  -- For AI-estimated entries (when food_id is NULL)
  food_name VARCHAR(255),
  ai_estimated BOOLEAN DEFAULT FALSE,
  ai_confidence VARCHAR(20) CHECK (ai_confidence IN ('high', 'medium', 'low')),

  -- Notes
  notes TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for efficient queries
CREATE INDEX idx_food_log_user_date ON food_log(user_id, log_date);
CREATE INDEX idx_food_log_user_date_meal ON food_log(user_id, log_date, meal_type);

-- Daily Summaries (materialized for performance)
CREATE TABLE daily_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  summary_date DATE NOT NULL,

  -- Totals
  total_calories DECIMAL(10,2) DEFAULT 0,
  total_protein DECIMAL(10,2) DEFAULT 0,
  total_carbs DECIMAL(10,2) DEFAULT 0,
  total_fat DECIMAL(10,2) DEFAULT 0,
  total_fiber DECIMAL(10,2) DEFAULT 0,
  total_sugar DECIMAL(10,2) DEFAULT 0,
  total_sodium DECIMAL(10,2) DEFAULT 0,

  -- Meal counts
  breakfast_calories DECIMAL(10,2) DEFAULT 0,
  lunch_calories DECIMAL(10,2) DEFAULT 0,
  dinner_calories DECIMAL(10,2) DEFAULT 0,
  snack_calories DECIMAL(10,2) DEFAULT 0,

  entries_count INTEGER DEFAULT 0,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, summary_date)
);

CREATE INDEX idx_daily_summaries_user_date ON daily_summaries(user_id, summary_date);

-- ============================================
-- FUNCTIONS
-- ============================================

-- Update timestamp function
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Update daily summary when food_log changes
CREATE OR REPLACE FUNCTION update_daily_summary()
RETURNS TRIGGER AS $$
DECLARE
  target_user_id UUID;
  target_date DATE;
BEGIN
  -- Determine which user and date to update
  IF TG_OP = 'DELETE' THEN
    target_user_id := OLD.user_id;
    target_date := OLD.log_date;
  ELSE
    target_user_id := NEW.user_id;
    target_date := NEW.log_date;
  END IF;

  -- Upsert daily summary
  INSERT INTO daily_summaries (user_id, summary_date, total_calories, total_protein, total_carbs, total_fat, total_fiber, total_sugar, total_sodium, breakfast_calories, lunch_calories, dinner_calories, snack_calories, entries_count)
  SELECT
    target_user_id,
    target_date,
    COALESCE(SUM(calories), 0),
    COALESCE(SUM(protein), 0),
    COALESCE(SUM(carbohydrates), 0),
    COALESCE(SUM(fat), 0),
    COALESCE(SUM(fiber), 0),
    COALESCE(SUM(sugar), 0),
    COALESCE(SUM(sodium), 0),
    COALESCE(SUM(CASE WHEN meal_type = 'breakfast' THEN calories ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN meal_type = 'lunch' THEN calories ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN meal_type = 'dinner' THEN calories ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN meal_type = 'snack' THEN calories ELSE 0 END), 0),
    COUNT(*)
  FROM food_log
  WHERE user_id = target_user_id AND log_date = target_date
  ON CONFLICT (user_id, summary_date)
  DO UPDATE SET
    total_calories = EXCLUDED.total_calories,
    total_protein = EXCLUDED.total_protein,
    total_carbs = EXCLUDED.total_carbs,
    total_fat = EXCLUDED.total_fat,
    total_fiber = EXCLUDED.total_fiber,
    total_sugar = EXCLUDED.total_sugar,
    total_sodium = EXCLUDED.total_sodium,
    breakfast_calories = EXCLUDED.breakfast_calories,
    lunch_calories = EXCLUDED.lunch_calories,
    dinner_calories = EXCLUDED.dinner_calories,
    snack_calories = EXCLUDED.snack_calories,
    entries_count = EXCLUDED.entries_count,
    updated_at = NOW();

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Auto-create profile on user signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO user_profiles (user_id, email)
  VALUES (NEW.id, NEW.email);

  -- Create default goals
  INSERT INTO user_goals (user_id, calories_target, protein_target, carbs_target, fat_target)
  VALUES (NEW.id, 2000, 50, 250, 65);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- TRIGGERS
-- ============================================

-- Updated_at triggers
CREATE TRIGGER tr_user_profiles_updated_at
  BEFORE UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER tr_user_goals_updated_at
  BEFORE UPDATE ON user_goals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER tr_foods_updated_at
  BEFORE UPDATE ON foods
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER tr_food_log_updated_at
  BEFORE UPDATE ON food_log
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Daily summary auto-update triggers
CREATE TRIGGER tr_food_log_summary_insert
  AFTER INSERT ON food_log
  FOR EACH ROW EXECUTE FUNCTION update_daily_summary();

CREATE TRIGGER tr_food_log_summary_update
  AFTER UPDATE ON food_log
  FOR EACH ROW EXECUTE FUNCTION update_daily_summary();

CREATE TRIGGER tr_food_log_summary_delete
  AFTER DELETE ON food_log
  FOR EACH ROW EXECUTE FUNCTION update_daily_summary();

-- New user trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================

-- Enable RLS on all tables
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE foods ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_servings ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_summaries ENABLE ROW LEVEL SECURITY;

-- User Profiles policies
CREATE POLICY "Users can view own profile"
  ON user_profiles FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update own profile"
  ON user_profiles FOR UPDATE
  USING (auth.uid() = user_id);

-- User Goals policies
CREATE POLICY "Users can view own goals"
  ON user_goals FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update own goals"
  ON user_goals FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own goals"
  ON user_goals FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Foods policies (readable by all authenticated, writable by creator)
CREATE POLICY "Authenticated users can view all foods"
  ON foods FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can create foods"
  ON foods FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Users can update their own foods"
  ON foods FOR UPDATE
  TO authenticated
  USING (auth.uid() = created_by);

-- Food Servings policies
CREATE POLICY "Authenticated users can view all servings"
  ON food_servings FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Food creators can manage servings"
  ON food_servings FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM foods
      WHERE foods.id = food_servings.food_id
      AND foods.created_by = auth.uid()
    )
  );

-- Food Log policies
CREATE POLICY "Users can view own log entries"
  ON food_log FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create own log entries"
  ON food_log FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own log entries"
  ON food_log FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own log entries"
  ON food_log FOR DELETE
  USING (auth.uid() = user_id);

-- Daily Summaries policies
CREATE POLICY "Users can view own summaries"
  ON daily_summaries FOR SELECT
  USING (auth.uid() = user_id);

-- Service role can manage summaries (for triggers)
CREATE POLICY "Service can manage summaries"
  ON daily_summaries FOR ALL
  TO service_role
  USING (true);

-- ============================================
-- SEED DATA (Common Foods)
-- ============================================

-- Insert some common generic foods from USDA-like data
INSERT INTO foods (name, brand, serving_size, serving_unit, serving_description, calories, protein, carbohydrates, fat, fiber, sugar, sodium, source, verified) VALUES
  ('Chicken Breast, Grilled', NULL, 100, 'g', '100g', 165, 31, 0, 3.6, 0, 0, 74, 'usda', true),
  ('Brown Rice, Cooked', NULL, 195, 'g', '1 cup cooked', 216, 5, 45, 1.8, 3.5, 0, 10, 'usda', true),
  ('Broccoli, Steamed', NULL, 91, 'g', '1 cup chopped', 31, 2.5, 6, 0.3, 2.4, 1.5, 30, 'usda', true),
  ('Egg, Large', NULL, 50, 'g', '1 large egg', 72, 6.3, 0.4, 5, 0, 0.2, 71, 'usda', true),
  ('Banana, Medium', NULL, 118, 'g', '1 medium banana', 105, 1.3, 27, 0.4, 3.1, 14, 1, 'usda', true),
  ('Apple, Medium', NULL, 182, 'g', '1 medium apple', 95, 0.5, 25, 0.3, 4.4, 19, 2, 'usda', true),
  ('Salmon, Atlantic, Cooked', NULL, 100, 'g', '100g', 208, 20, 0, 13, 0, 0, 59, 'usda', true),
  ('Greek Yogurt, Plain, Nonfat', NULL, 170, 'g', '1 container (6 oz)', 100, 17, 6, 0.7, 0, 4, 56, 'usda', true),
  ('Oatmeal, Cooked', NULL, 234, 'g', '1 cup cooked', 158, 6, 27, 3.2, 4, 1, 115, 'usda', true),
  ('Avocado', NULL, 150, 'g', '1 medium avocado', 240, 3, 12, 22, 10, 1, 11, 'usda', true),
  ('Sweet Potato, Baked', NULL, 200, 'g', '1 medium', 180, 4, 41, 0.2, 6.6, 13, 72, 'usda', true),
  ('Almonds', NULL, 28, 'g', '1 oz (23 almonds)', 164, 6, 6, 14, 3.5, 1.2, 0, 'usda', true),
  ('Spinach, Raw', NULL, 30, 'g', '1 cup', 7, 0.9, 1.1, 0.1, 0.7, 0.1, 24, 'usda', true),
  ('Whole Wheat Bread', NULL, 43, 'g', '1 slice', 81, 4, 14, 1.1, 1.9, 1.4, 146, 'usda', true),
  ('Olive Oil', NULL, 14, 'g', '1 tablespoon', 119, 0, 0, 13.5, 0, 0, 0, 'usda', true)
ON CONFLICT DO NOTHING;

-- Add serving alternatives for some foods
INSERT INTO food_servings (food_id, name, amount, unit, gram_equivalent)
SELECT id, '1 oz', 1, 'oz', 28.35 FROM foods WHERE name = 'Chicken Breast, Grilled'
UNION ALL
SELECT id, '4 oz', 4, 'oz', 113.4 FROM foods WHERE name = 'Chicken Breast, Grilled'
UNION ALL
SELECT id, '6 oz', 6, 'oz', 170 FROM foods WHERE name = 'Chicken Breast, Grilled'
UNION ALL
SELECT id, '1/2 cup', 0.5, 'cup', 98 FROM foods WHERE name = 'Brown Rice, Cooked'
UNION ALL
SELECT id, '2 eggs', 2, 'eggs', 100 FROM foods WHERE name = 'Egg, Large'
UNION ALL
SELECT id, '1 small', 1, 'small', 101 FROM foods WHERE name = 'Banana, Medium'
UNION ALL
SELECT id, '1 large', 1, 'large', 136 FROM foods WHERE name = 'Banana, Medium';
