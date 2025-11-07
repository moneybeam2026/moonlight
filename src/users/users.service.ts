import { Injectable } from '@nestjs/common';

export interface User {
  id: number;
  firstName: string;
  lastName: string;
  email: string;
  age: number;
  city: string;
  createdAt: Date;
}

@Injectable()
export class UsersService {
  private users: User[] = [
    {
      id: 1,
      firstName: 'John',
      lastName: 'Does',
      email: 'john.does@example.com',
      age: 28,
      city: 'New York',
      createdAt: new Date('2024-01-15'),
    },
    {
      id: 2,
      firstName: 'Jane',
      lastName: 'Smith',
      email: 'jane.smith@example.com',
      age: 32,
      city: 'San Francisco',
      createdAt: new Date('2024-02-20'),
    },
    {
      id: 3,
      firstName: 'Michael',
      lastName: 'Johnson',
      email: 'michael.johnson@example.com',
      age: 45,
      city: 'Chicago',
      createdAt: new Date('2024-03-10'),
    },
    {
      id: 4,
      firstName: 'Emily',
      lastName: 'Davis',
      email: 'emily.davis@example.com',
      age: 26,
      city: 'Austin',
      createdAt: new Date('2024-04-05'),
    },
    {
      id: 5,
      firstName: 'David',
      lastName: 'Wilson',
      email: 'david.wilson@example.com',
      age: 38,
      city: 'Seattle',
      createdAt: new Date('2024-05-12'),
    },
  ];

  findAll(): User[] {
    return this.users;
  }

  findOne(id: number): User {
    return this.users.find(user => user.id === id);
  }

  create(userData: Omit<User, 'id' | 'createdAt'>): User {
    const newUser: User = {
      id: this.users.length + 1,
      ...userData,
      createdAt: new Date(),
    };
    this.users.push(newUser);
    return newUser;
  }

  update(id: number, userData: Partial<Omit<User, 'id' | 'createdAt'>>): User {
    const userIndex = this.users.findIndex(user => user.id === id);
    if (userIndex === -1) {
      return null;
    }
    this.users[userIndex] = { ...this.users[userIndex], ...userData };
    return this.users[userIndex];
  }

  delete(id: number): boolean {
    const userIndex = this.users.findIndex(user => user.id === id);
    if (userIndex === -1) {
      return false;
    }
    this.users.splice(userIndex, 1);
    return true;
  }
}
