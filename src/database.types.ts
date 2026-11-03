export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  public: {
    Tables: {
      loans: {
        Row: {
          borrower_id: string;
          created_at: string;
          ends_on: string;
          id: string;
          starts_on: string;
          status: string;
          tool_id: string;
        };
        ComputedFields: never;
        Insert: {
          borrower_id?: string;
          created_at?: string;
          ends_on: string;
          id?: string;
          starts_on: string;
          status?: string;
          tool_id: string;
        };
        Update: {
          borrower_id?: string;
          created_at?: string;
          ends_on?: string;
          id?: string;
          starts_on?: string;
          status?: string;
          tool_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'loans_borrower_id_fkey';
            columns: ['borrower_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'loans_tool_id_fkey';
            columns: ['tool_id'];
            isOneToOne: false;
            referencedRelation: 'tools';
            referencedColumns: ['id'];
          },
        ];
      };
      profiles: {
        Row: {
          display_name: string;
          id: string;
        };
        ComputedFields: never;
        Insert: {
          display_name: string;
          id: string;
        };
        Update: {
          display_name?: string;
          id?: string;
        };
        Relationships: [];
      };
      tools: {
        Row: {
          category: string;
          created_at: string;
          id: string;
          is_available: boolean;
          name: string;
          owner_id: string;
        };
        ComputedFields: never;
        Insert: {
          category: string;
          created_at?: string;
          id?: string;
          is_available?: boolean;
          name: string;
          owner_id?: string;
        };
        Update: {
          category?: string;
          created_at?: string;
          id?: string;
          is_available?: boolean;
          name?: string;
          owner_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'tools_owner_id_fkey';
            columns: ['owner_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      user_roles: {
        Row: {
          role: string;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          role: string;
          user_id: string;
        };
        Update: {
          role?: string;
          user_id?: string;
        };
        Relationships: [];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      admin_list_loans: {
        Args: { p_limit?: number; p_offset?: number };
        Returns: {
          borrower_id: string;
          created_at: string;
          ends_on: string;
          loan_id: string;
          owner_id: string;
          starts_on: string;
          status: string;
          tool_id: string;
          tool_name: string;
        }[];
      };
      decide_loan: {
        Args: { p_decision: string; p_loan_id: string };
        Returns: {
          borrower_id: string;
          created_at: string;
          ends_on: string;
          id: string;
          starts_on: string;
          status: string;
          tool_id: string;
        };
        SetofOptions: {
          from: '*';
          to: 'loans';
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      request_loan: {
        Args: { p_ends_on: string; p_starts_on: string; p_tool_id: string };
        Returns: {
          borrower_id: string;
          created_at: string;
          ends_on: string;
          id: string;
          starts_on: string;
          status: string;
          tool_id: string;
        };
        SetofOptions: {
          from: '*';
          to: 'loans';
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>;

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, 'public'>];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    ? (DefaultSchema['Tables'] & DefaultSchema['Views'])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema['Enums'] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums']
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums'][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema['Enums']
    ? DefaultSchema['Enums'][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    keyof DefaultSchema['CompositeTypes'] | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes']
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes'][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema['CompositeTypes']
    ? DefaultSchema['CompositeTypes'][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  public: {
    Enums: {},
  },
} as const;
