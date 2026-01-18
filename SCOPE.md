# FoodNoms Clone - Technical Scope Document

## Project Overview

A web-based nutrition tracking application that clones the core functionality of FoodNoms, built with **Next.js 14+**, **Supabase**, and **Google Gemini Flash** for AI-powered food recognition.

### Tech Stack
- **Frontend**: Next.js 14+ (App Router), React 18, TypeScript, Tailwind CSS
- **UI Components**: shadcn/ui (Radix UI primitives + Tailwind)
- **Backend**: Next.js API Routes (Route Handlers)
- **Database**: Supabase (PostgreSQL)
- **Authentication**: Supabase Auth (email/password)
- **AI/ML**: Google Gemini Flash (image recognition, OCR, food estimation)
- **External APIs**: Open Food Facts (barcode lookup), USDA FoodData Central (nutrition data)
- **Image Processing**: Browser MediaDevices API for camera access
- **Charts**: Recharts (shadcn/ui charts)
- **Forms**: React Hook Form + Zod validation
- **Barcode**: @zxing/browser for barcode detection
- **Deployment**: Vercel

### Design Principles
- **Color scheme**: Black and white only (monochrome)
- **Default units**: Imperial (oz, cups, lbs) with option to switch to metric
- **UI philosophy**: Simple, clean, minimal - no fancy animations or decorations

---

## Feature Breakdown

### 1. Authentication System

**Description**: Simple email/password authentication using Supabase Auth.

**User Stories**:
- As a user, I can sign up with email and password
- As a user, I can log in to access my data
- As a user, I can reset my password via email
- As a user, I can log out

**Technical Implementation**:
- Supabase Auth with `@supabase/ssr` for Next.js
- Protected routes using middleware
- Session management with cookies

**Components**:
- `SignUpForm` - Registration form
- `LoginForm` - Login form
- `ForgotPasswordForm` - Password reset request
- `ResetPasswordForm` - New password form

---

### 2. Food Database System

**Description**: Multi-source food database combining external APIs with user contributions.

**Data Sources**:
1. **Open Food Facts API** - Barcode lookups (free, 3M+ products)
2. **USDA FoodData Central** - Comprehensive nutrition data (public domain)
3. **User Contributions** - Community-added foods stored in Supabase

**User Stories**:
- As a user, I can search for foods by name
- As a user, I can look up foods by barcode
- As a user, I can add new foods to the database
- As a user, I can see nutrition info including calories, protein, carbs, fat, fiber, etc.

**Database Tables**:

```sql
-- User-contributed foods
CREATE TABLE foods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by UUID REFERENCES auth.users(id),
  barcode VARCHAR(50) UNIQUE,
  name VARCHAR(255) NOT NULL,
  brand VARCHAR(255),

  -- Per serving nutrition
  serving_size DECIMAL(10,2) NOT NULL,
  serving_unit VARCHAR(50) NOT NULL, -- 'g', 'ml', 'oz', 'cup', etc.

  -- Macros (per serving)
  calories DECIMAL(10,2),
  protein DECIMAL(10,2),
  carbohydrates DECIMAL(10,2),
  fat DECIMAL(10,2),
  fiber DECIMAL(10,2),
  sugar DECIMAL(10,2),
  sodium DECIMAL(10,2),
  saturated_fat DECIMAL(10,2),
  cholesterol DECIMAL(10,2),

  -- Metadata
  verified BOOLEAN DEFAULT FALSE,
  source VARCHAR(50) DEFAULT 'user', -- 'user', 'usda', 'openfoodfacts'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Alternative serving sizes for foods
CREATE TABLE food_servings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  food_id UUID REFERENCES foods(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL, -- '1 cup', '1 slice', '100g'
  amount DECIMAL(10,2) NOT NULL,
  unit VARCHAR(50) NOT NULL,
  gram_equivalent DECIMAL(10,2), -- For conversion
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**API Endpoints**:
- `GET /api/foods/search?q={query}` - Search foods by name
- `GET /api/foods/barcode/{barcode}` - Lookup by barcode
- `POST /api/foods` - Add new food
- `GET /api/foods/{id}` - Get food details
- `PUT /api/foods/{id}` - Update food (creator only)

**Search Logic**:
1. Search local Supabase database first
2. If barcode not found locally, query Open Food Facts
3. For text search, also query USDA FoodData Central
4. Cache external results locally for faster future lookups

---

### 3. Barcode Scanner

**Description**: Camera-based barcode scanning using the device camera.

**User Stories**:
- As a user, I can scan a product barcode with my camera
- As a user, I see the product's nutrition info after scanning
- As a user, I can add the scanned product to my food log
- As a user, I can add a new food if the barcode isn't found

**Technical Implementation**:
- Use `react-zxing` or `@zxing/browser` for barcode detection
- Access camera via `navigator.mediaDevices.getUserMedia()`
- Support common formats: EAN-13, EAN-8, UPC-A, UPC-E

**Components**:
- `BarcodeScanner` - Camera viewfinder with barcode detection
- `BarcodeScanResult` - Display found product or "not found" state
- `AddFoodFromBarcode` - Form to add new food when barcode not found

**Flow**:
1. User opens scanner → camera activates
2. Barcode detected → API lookup
3. Found → show nutrition, option to log
4. Not found → prompt to add new food with barcode pre-filled

---

### 4. AI Photo Meal Scanner (Gemini Flash)

**Description**: Take a photo of food, AI identifies items and estimates nutrition.

**User Stories**:
- As a user, I can take a photo of my meal
- As a user, I see AI-identified food items with estimated portions
- As a user, I can adjust the AI's estimates before logging
- As a user, I can add optional context (e.g., "this is a small portion")

**Technical Implementation**:

**Gemini Flash Integration**:
```typescript
// Prompt structure for food recognition
const prompt = `
Analyze this food image and identify all food items visible.
For each item, provide:
1. Food name (be specific, e.g., "grilled chicken breast" not just "chicken")
2. Estimated portion size in grams
3. Estimated calories
4. Estimated macros (protein, carbs, fat in grams)

Consider visible context clues for portion estimation:
- Plate/bowl size
- Utensils for scale
- Any visible packaging

Return as JSON:
{
  "items": [
    {
      "name": "string",
      "portion_grams": number,
      "calories": number,
      "protein": number,
      "carbs": number,
      "fat": number,
      "confidence": "high" | "medium" | "low"
    }
  ],
  "total_calories": number,
  "notes": "string (any caveats about the estimation)"
}
`;
```

**API Endpoint**:
- `POST /api/ai/analyze-meal` - Send image, get food analysis
  - Input: Base64 image or image URL
  - Optional: User context/notes
  - Output: JSON with identified items and nutrition estimates

**Components**:
- `MealPhotoCapture` - Camera interface for taking meal photos
- `MealAnalysisResult` - Display AI results with edit capability
- `MealItemEditor` - Adjust individual item estimates
- `ConfirmMealLog` - Review and confirm before logging

**AI Response Handling**:
1. Display AI results with confidence indicators
2. Allow user to edit any values
3. Cross-reference with local database for more accurate data
4. Option to search and replace AI estimate with database food

---

### 5. Nutrition Label OCR Scanner

**Description**: Scan nutrition facts labels to extract data when barcode lookup fails.

**User Stories**:
- As a user, I can scan a nutrition label with my camera
- As a user, I see extracted nutrition data for review
- As a user, I can correct any OCR errors
- As a user, I can save the food to the database

**Technical Implementation**:

**Gemini Flash OCR Prompt**:
```typescript
const ocrPrompt = `
Extract the nutrition facts from this nutrition label image.
Parse all available information and return as JSON:

{
  "serving_size": {
    "amount": number,
    "unit": "string (g, ml, oz, cup, etc.)",
    "description": "string (e.g., '1 cup (240ml)')"
  },
  "servings_per_container": number | null,
  "nutrients": {
    "calories": number,
    "total_fat": number,
    "saturated_fat": number | null,
    "trans_fat": number | null,
    "cholesterol": number | null,
    "sodium": number | null,
    "total_carbohydrates": number,
    "dietary_fiber": number | null,
    "total_sugars": number | null,
    "added_sugars": number | null,
    "protein": number
  },
  "confidence": "high" | "medium" | "low",
  "notes": "string (any issues or uncertainties)"
}

All nutrient values should be in their standard units (g for macros, mg for sodium/cholesterol).
If a value is not visible or unclear, use null.
`;
```

**API Endpoint**:
- `POST /api/ai/scan-label` - Send label image, get nutrition data

**Components**:
- `LabelScanner` - Camera interface optimized for label capture
- `LabelScanResult` - Display extracted data with edit capability
- `LabelDataEditor` - Form to correct OCR errors
- `SaveFoodFromLabel` - Save as new food with name/brand input

**Flow**:
1. User scans barcode → not found
2. Prompt: "Scan nutrition label instead?"
3. User captures label image
4. AI extracts nutrition data
5. User reviews/corrects and adds food name/brand
6. Save to database with barcode

---

### 6. Food Logging System

**Description**: Core meal logging functionality with portions and meal organization.

**User Stories**:
- As a user, I can log foods to specific meals (breakfast, lunch, dinner, snacks)
- As a user, I can specify portion sizes
- As a user, I can see my logged foods for the day
- As a user, I can edit or delete logged entries
- As a user, I can view logs for any date

**Database Tables**:

```sql
-- Daily food log entries
CREATE TABLE food_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  food_id UUID REFERENCES foods(id), -- NULL for AI-estimated foods

  -- Log details
  log_date DATE NOT NULL,
  meal_type VARCHAR(20) NOT NULL, -- 'breakfast', 'lunch', 'dinner', 'snack'

  -- Portion
  servings DECIMAL(10,2) NOT NULL DEFAULT 1,
  serving_id UUID REFERENCES food_servings(id), -- Which serving size used

  -- Actual nutrition logged (calculated at log time)
  calories DECIMAL(10,2),
  protein DECIMAL(10,2),
  carbohydrates DECIMAL(10,2),
  fat DECIMAL(10,2),
  fiber DECIMAL(10,2),

  -- For AI-estimated entries without food_id
  food_name VARCHAR(255),
  ai_estimated BOOLEAN DEFAULT FALSE,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for efficient date queries
CREATE INDEX idx_food_log_user_date ON food_log(user_id, log_date);
```

**API Endpoints**:
- `GET /api/log?date={date}` - Get logs for a date
- `POST /api/log` - Add log entry
- `PUT /api/log/{id}` - Update log entry
- `DELETE /api/log/{id}` - Delete log entry
- `GET /api/log/summary?date={date}` - Get daily nutrition summary

**Components**:
- `DailyLog` - Main daily view with meals
- `MealSection` - Collapsible meal section (breakfast, lunch, etc.)
- `LogEntry` - Individual logged food item
- `AddFoodToMeal` - Search and add food to meal
- `PortionSelector` - Choose serving size and quantity
- `QuickLogButton` - Floating action button for quick logging

---

### 7. Goals & Tracking System

**Description**: Set nutrition goals and track progress over time.

**User Stories**:
- As a user, I can set daily calorie and macro goals
- As a user, I can see my progress against goals
- As a user, I can view weekly/monthly trends
- As a user, I can see remaining calories/macros for the day

**Database Tables**:

```sql
-- User nutrition goals
CREATE TABLE user_goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,

  -- Daily targets
  calories_target INTEGER,
  protein_target INTEGER, -- grams
  carbs_target INTEGER,   -- grams
  fat_target INTEGER,     -- grams
  fiber_target INTEGER,   -- grams
  water_target INTEGER,   -- ml

  -- Goal type
  goal_type VARCHAR(50), -- 'lose_weight', 'maintain', 'gain_muscle', 'custom'

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Daily summaries (materialized for performance)
CREATE TABLE daily_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  summary_date DATE NOT NULL,

  total_calories DECIMAL(10,2) DEFAULT 0,
  total_protein DECIMAL(10,2) DEFAULT 0,
  total_carbs DECIMAL(10,2) DEFAULT 0,
  total_fat DECIMAL(10,2) DEFAULT 0,
  total_fiber DECIMAL(10,2) DEFAULT 0,

  meals_logged INTEGER DEFAULT 0,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, summary_date)
);
```

**API Endpoints**:
- `GET /api/goals` - Get user's goals
- `PUT /api/goals` - Update goals
- `GET /api/stats/daily?date={date}` - Get daily summary
- `GET /api/stats/weekly?start={date}` - Get weekly stats
- `GET /api/stats/monthly?month={month}` - Get monthly stats

**Components**:
- `GoalSetup` - Initial goal configuration wizard
- `GoalEditor` - Edit existing goals
- `DailyProgress` - Circular/bar progress indicators
- `MacroBreakdown` - Visual macro distribution
- `WeeklyChart` - 7-day trend chart
- `MonthlyCalendar` - Calendar heatmap view

---

### 8. User Profile & Settings

**Description**: User preferences and account management.

**Database Tables**:

```sql
CREATE TABLE user_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,

  display_name VARCHAR(100),

  -- Preferences
  default_meal_type VARCHAR(20) DEFAULT 'snack',
  use_metric BOOLEAN DEFAULT TRUE, -- metric vs imperial

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Components**:
- `ProfilePage` - Account overview
- `SettingsPage` - App preferences
- `UnitToggle` - Metric/Imperial switch

---

## API Architecture

### External API Integrations

**1. Open Food Facts**
```typescript
// Barcode lookup
GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json

// Rate limit: 100 req/min for reads
```

**2. USDA FoodData Central**
```typescript
// Search foods
GET https://api.nal.usda.gov/fdc/v1/foods/search?query={query}&api_key={key}

// Get food details
GET https://api.nal.usda.gov/fdc/v1/food/{fdcId}?api_key={key}

// Rate limit: 1000 req/hour
```

**3. Google Gemini Flash**
```typescript
// Using @google/generative-ai SDK
import { GoogleGenerativeAI } from "@google/generative-ai";

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

// For image analysis
const result = await model.generateContent([prompt, imagePart]);
```

### API Route Structure

```
/api
├── /auth
│   ├── /signup          POST - Register user
│   ├── /login           POST - Login
│   └── /logout          POST - Logout
├── /foods
│   ├── /search          GET  - Search foods
│   ├── /barcode/[code]  GET  - Barcode lookup
│   ├── /[id]            GET  - Food details
│   └── /                POST - Add food
├── /log
│   ├── /                GET  - Get daily log
│   ├── /                POST - Add entry
│   ├── /[id]            PUT  - Update entry
│   ├── /[id]            DELETE - Remove entry
│   └── /summary         GET  - Daily summary
├── /goals
│   ├── /                GET  - Get goals
│   └── /                PUT  - Update goals
├── /stats
│   ├── /daily           GET  - Daily stats
│   ├── /weekly          GET  - Weekly stats
│   └── /monthly         GET  - Monthly stats
├── /ai
│   ├── /analyze-meal    POST - Photo food analysis
│   └── /scan-label      POST - Nutrition label OCR
└── /user
    └── /profile         GET/PUT - User profile
```

---

## Component Architecture

### Page Structure (App Router)

```
/app
├── /(auth)
│   ├── /login/page.tsx
│   ├── /signup/page.tsx
│   └── /forgot-password/page.tsx
├── /(main)
│   ├── /layout.tsx          - Main app layout with nav
│   ├── /page.tsx            - Dashboard/Daily log
│   ├── /scan/page.tsx       - Barcode scanner
│   ├── /photo/page.tsx      - Photo meal scanner
│   ├── /search/page.tsx     - Food search
│   ├── /add-food/page.tsx   - Add custom food
│   ├── /goals/page.tsx      - Goals management
│   ├── /stats/page.tsx      - Statistics/trends
│   └── /settings/page.tsx   - User settings
└── /api/...                  - API routes
```

### Shared Components

```
/components
├── /ui                    - Base UI components (shadcn/ui)
│   ├── button.tsx
│   ├── card.tsx
│   ├── input.tsx
│   ├── dialog.tsx
│   └── ...
├── /food
│   ├── FoodCard.tsx       - Display food with nutrition
│   ├── FoodSearch.tsx     - Search input with results
│   ├── NutritionFacts.tsx - Nutrition label display
│   └── PortionPicker.tsx  - Serving size selector
├── /scanner
│   ├── BarcodeScanner.tsx - Barcode camera scanner
│   ├── LabelScanner.tsx   - Nutrition label scanner
│   └── MealCamera.tsx     - Photo meal capture
├── /log
│   ├── DailyLog.tsx       - Daily meal log view
│   ├── MealSection.tsx    - Meal group component
│   ├── LogEntry.tsx       - Single log entry
│   └── QuickAdd.tsx       - Quick add FAB
├── /progress
│   ├── CalorieRing.tsx    - Circular progress
│   ├── MacroBar.tsx       - Macro progress bar
│   └── WeeklyChart.tsx    - Weekly trend chart
└── /layout
    ├── Header.tsx         - App header
    ├── BottomNav.tsx      - Mobile navigation
    └── Sidebar.tsx        - Desktop sidebar
```

---

## Database Schema Summary

```
┌─────────────────┐     ┌─────────────────┐
│   auth.users    │     │  user_profiles  │
│   (Supabase)    │────▶│                 │
└────────┬────────┘     └─────────────────┘
         │
         │  ┌─────────────────┐
         ├─▶│   user_goals    │
         │  └─────────────────┘
         │
         │  ┌─────────────────┐     ┌─────────────────┐
         ├─▶│    food_log     │────▶│     foods       │
         │  └─────────────────┘     └────────┬────────┘
         │                                   │
         │  ┌─────────────────┐              │
         ├─▶│ daily_summaries │     ┌────────▼────────┐
         │  └─────────────────┘     │  food_servings  │
         │                          └─────────────────┘
         │
         └─▶│     foods       │ (created_by)
```

---

## Environment Variables

```env
# Supabase
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=

# External APIs
GEMINI_API_KEY=
USDA_API_KEY=

# App
NEXT_PUBLIC_APP_URL=http://localhost:3000
```

---

## Security Considerations

1. **Row Level Security (RLS)** - All Supabase tables use RLS policies
   - Users can only read/write their own log entries
   - Foods are readable by all, writable by creator

2. **API Rate Limiting** - Implement rate limiting on AI endpoints
   - Gemini calls: 10 req/min per user

3. **Input Validation** - Validate all inputs with Zod schemas

4. **Image Handling** - Validate image types and sizes before AI processing

---

## Performance Optimizations

1. **Database Indexes** - On frequently queried columns
2. **API Response Caching** - Cache Open Food Facts/USDA responses
3. **Image Compression** - Compress images before sending to Gemini
4. **Daily Summary Materialization** - Pre-compute daily totals

---

## Mobile Responsiveness

The app will be fully responsive with:
- Mobile-first design approach
- Bottom navigation for mobile
- Sidebar navigation for desktop
- Touch-friendly controls for scanning features
- PWA capabilities for app-like experience

---

## Shadcn/UI Component Mapping

### Required Shadcn Components to Install

```bash
npx shadcn@latest init
npx shadcn@latest add button card input label form dialog sheet
npx shadcn@latest add dropdown-menu avatar tabs progress badge
npx shadcn@latest add select slider separator skeleton toast
npx shadcn@latest add command popover calendar collapsible
npx shadcn@latest add alert-dialog scroll-area table chart
```

### Component-to-Feature Mapping

| Feature | Shadcn Components Used |
|---------|------------------------|
| **Auth Forms** | `Card`, `Form`, `Input`, `Label`, `Button` |
| **Food Search** | `Command` (cmdk), `Popover`, `Input`, `Skeleton` |
| **Food Cards** | `Card`, `Badge`, `Button`, `Separator` |
| **Nutrition Display** | `Card`, `Progress`, `Separator`, `Table` |
| **Portion Picker** | `Select`, `Slider`, `Input`, `Popover` |
| **Meal Sections** | `Collapsible`, `Card`, `Button`, `Badge` |
| **Log Entry** | `Card`, `Button`, `DropdownMenu`, `AlertDialog` |
| **Quick Add FAB** | `Button`, `Sheet`, `Command` |
| **Daily Progress** | `Progress`, `Card`, `Chart` (radial) |
| **Macro Bars** | `Progress`, `Badge`, `Card` |
| **Weekly Chart** | `Chart` (bar/line), `Card`, `Tabs` |
| **Goals Editor** | `Form`, `Input`, `Slider`, `Select`, `Card` |
| **Date Picker** | `Calendar`, `Popover`, `Button` |
| **Scanner Overlay** | `Dialog`, `Button`, `Card` |
| **AI Results** | `Card`, `Skeleton`, `Badge`, `Table`, `Button` |
| **Settings** | `Card`, `Switch`, `Select`, `Separator` |
| **Bottom Nav** | `Button`, custom styling |
| **Toasts/Alerts** | `Toast`, `AlertDialog` |

### Custom Components Built on Shadcn

```
/components
├── /ui                          # Shadcn primitives (auto-generated)
│   ├── button.tsx
│   ├── card.tsx
│   ├── command.tsx
│   ├── dialog.tsx
│   ├── form.tsx
│   ├── input.tsx
│   ├── progress.tsx
│   ├── select.tsx
│   ├── sheet.tsx
│   ├── skeleton.tsx
│   ├── slider.tsx
│   ├── tabs.tsx
│   ├── toast.tsx
│   └── ...
│
├── /food                        # Food-specific components
│   ├── FoodCard.tsx             # Card + Badge + Progress
│   ├── FoodSearchCommand.tsx    # Command + Popover (combobox pattern)
│   ├── NutritionLabel.tsx       # Card + Table + Progress bars
│   ├── PortionPicker.tsx        # Select + Slider + Input
│   └── MacroRing.tsx            # Custom SVG ring using Chart colors
│
├── /scanner                     # Camera components
│   ├── CameraView.tsx           # Custom (canvas + video)
│   ├── BarcodeScanner.tsx       # Dialog + CameraView + Card
│   ├── MealPhotoCapture.tsx     # Sheet + CameraView + Button
│   └── LabelScanner.tsx         # Dialog + CameraView + Form
│
├── /log                         # Logging components
│   ├── DailyLogView.tsx         # Card + Collapsible + ScrollArea
│   ├── MealSection.tsx          # Collapsible + Badge + Button
│   ├── LogEntryCard.tsx         # Card + DropdownMenu + AlertDialog
│   ├── QuickAddSheet.tsx        # Sheet + Command + Form
│   └── DateNavigator.tsx        # Button + Calendar + Popover
│
├── /progress                    # Stats & visualization
│   ├── CalorieRingChart.tsx     # Chart (radial) + Card
│   ├── MacroProgressBars.tsx    # Progress + Badge
│   ├── WeeklyBarChart.tsx       # Chart (bar) + Tabs
│   └── NutrientSummary.tsx      # Card + Table + Progress
│
├── /goals                       # Goal management
│   ├── GoalSetupWizard.tsx      # Dialog + Form + Slider + Select
│   ├── GoalCard.tsx             # Card + Progress + Button
│   └── MacroGoalSliders.tsx     # Slider + Label + Input
│
└── /layout                      # App shell
    ├── AppHeader.tsx            # Avatar + DropdownMenu + Button
    ├── BottomNav.tsx            # Custom nav with Button styling
    ├── Sidebar.tsx              # Sheet (mobile) + nav links
    └── PageContainer.tsx        # ScrollArea + consistent padding
```

### Key UI Patterns

**1. Food Search (Combobox Pattern)**
```tsx
// Uses Command + Popover for searchable food list
<Popover>
  <PopoverTrigger asChild>
    <Button variant="outline">Search foods...</Button>
  </PopoverTrigger>
  <PopoverContent>
    <Command>
      <CommandInput placeholder="Search..." />
      <CommandList>
        <CommandEmpty>No foods found</CommandEmpty>
        <CommandGroup heading="Recent">
          <CommandItem>Chicken Breast</CommandItem>
        </CommandGroup>
        <CommandGroup heading="Results">
          {searchResults.map(food => (
            <CommandItem key={food.id}>{food.name}</CommandItem>
          ))}
        </CommandGroup>
      </CommandList>
    </Command>
  </PopoverContent>
</Popover>
```

**2. Meal Section (Collapsible Pattern)**
```tsx
<Collapsible defaultOpen>
  <CollapsibleTrigger asChild>
    <Button variant="ghost" className="w-full justify-between">
      <span>Breakfast</span>
      <Badge>{mealCalories} cal</Badge>
    </Button>
  </CollapsibleTrigger>
  <CollapsibleContent>
    {entries.map(entry => <LogEntryCard key={entry.id} {...entry} />)}
    <Button variant="outline" size="sm">+ Add Food</Button>
  </CollapsibleContent>
</Collapsible>
```

**3. Quick Add (Sheet Pattern)**
```tsx
<Sheet>
  <SheetTrigger asChild>
    <Button size="lg" className="fixed bottom-20 right-4 rounded-full">
      +
    </Button>
  </SheetTrigger>
  <SheetContent side="bottom" className="h-[80vh]">
    <SheetHeader>
      <SheetTitle>Add Food</SheetTitle>
    </SheetHeader>
    <Tabs defaultValue="search">
      <TabsList>
        <TabsTrigger value="search">Search</TabsTrigger>
        <TabsTrigger value="scan">Scan</TabsTrigger>
        <TabsTrigger value="photo">Photo</TabsTrigger>
      </TabsList>
      <TabsContent value="search">
        <FoodSearchCommand onSelect={handleAddFood} />
      </TabsContent>
      <TabsContent value="scan">
        <BarcodeScanner onScan={handleBarcode} />
      </TabsContent>
      <TabsContent value="photo">
        <MealPhotoCapture onCapture={handlePhoto} />
      </TabsContent>
    </Tabs>
  </SheetContent>
</Sheet>
```

**4. Daily Progress (Radial Chart)**
```tsx
<Card>
  <CardContent className="flex items-center gap-4">
    <ChartContainer config={chartConfig}>
      <RadialBarChart data={[{ calories: consumed, fill: "var(--chart-1)" }]}>
        <RadialBar dataKey="calories" background />
        <PolarRadiusAxis tick={false} domain={[0, goal]} />
      </RadialBarChart>
    </ChartContainer>
    <div>
      <p className="text-2xl font-bold">{consumed}</p>
      <p className="text-muted-foreground">of {goal} cal</p>
    </div>
  </CardContent>
</Card>
```

---

## Implementation Phases

### Phase 1: Foundation
- Next.js project setup with TypeScript
- Shadcn/ui installation and theme configuration
- Supabase project + schema deployment
- Auth flow (signup, login, logout)
- Basic layout (header, bottom nav, page containers)

### Phase 2: Core Food Features
- Food database tables + seed data
- Food search with Command component
- Add custom food form
- Nutrition display components

### Phase 3: Logging System
- Daily log view with meal sections
- Add food to meal flow
- Portion picker with serving sizes
- Edit/delete log entries
- Date navigation

### Phase 4: Scanner Features
- Camera access component
- Barcode scanner with @zxing/browser
- Open Food Facts API integration
- Photo meal capture
- Gemini Flash integration for food analysis
- Nutrition label OCR

### Phase 5: Goals & Stats
- Goal setup/edit forms
- Daily progress display
- Macro breakdown visualization
- Weekly/monthly charts

### Phase 6: Polish
- Loading states with Skeleton
- Error handling with Toast
- Responsive design refinement
- PWA manifest + icons

---

## Future Enhancements (Post-MVP)

1. Recipe creation and meal planning
2. Water tracking
3. Weight tracking integration
4. Social features (share meals)
5. Export data (CSV/PDF)
6. Apple Health / Google Fit sync
7. Meal reminders/notifications
