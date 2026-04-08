import Head from 'next/head';
import type {
  GetServerSideProps,
  InferGetServerSidePropsType,
} from 'next';

type Todo = {
  id: number | string;
  name: string;
};

type TodosPageProps = {
  todos: Todo[];
};

export const getServerSideProps: GetServerSideProps<TodosPageProps> = async () => {
  return {
    notFound: true,
  };
};

export default function TodosPage({
  todos,
}: InferGetServerSidePropsType<typeof getServerSideProps>) {
  return (
    <>
      <Head>
        <title>Aveli Att göra</title>
      </Head>
      <main>
        <ul>
          {todos.map((todo) => (
            <li key={todo.id}>{todo.name}</li>
          ))}
        </ul>
      </main>
    </>
  );
}
